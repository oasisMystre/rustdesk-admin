import 'dart:async';

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:draggable_float_widget/draggable_float_widget.dart';

import 'model.dart';
import '../common.dart';
import '../common/widgets/overlay.dart';

class MessageKey {
  final String peerId;
  final int connId;
  bool get isOut => connId == ChatModel.clientModeID;

  MessageKey(this.peerId, this.connId);

  @override
  bool operator ==(other) {
    return other is MessageKey &&
        other.peerId == peerId &&
        other.isOut == isOut;
  }

  @override
  int get hashCode => peerId.hashCode ^ isOut.hashCode;
}

class MessageBody {
  ChatUser chatUser;
  List<ChatMessage> chatMessages;
  MessageBody(this.chatUser, this.chatMessages);

  void insert(ChatMessage cm) {
    chatMessages.insert(0, cm);
  }

  void clear() {
    chatMessages.clear();
  }
}

class ChatModel with ChangeNotifier {
  static final clientModeID = -1;

  OverlayEntry? chatIconOverlayEntry;
  OverlayEntry? chatWindowOverlayEntry;

  bool isConnManager = false;

  RxBool isWindowFocus = true.obs;
  BlockableOverlayState _blockableOverlayState = BlockableOverlayState();
  final Rx<VoiceCallStatus> _voiceCallStatus = Rx(VoiceCallStatus.notStarted);

  Rx<VoiceCallStatus> get voiceCallStatus => _voiceCallStatus;

  TextEditingController textController = TextEditingController();
  RxInt mobileUnreadSum = 0.obs;
  MessageKey? latestReceivedKey;

  Offset chatWindowPosition = Offset(20, 80);

  void setChatWindowPosition(Offset position) {
    chatWindowPosition = position;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  final ChatUser me = ChatUser(
    id: Uuid().v4().toString(),
    firstName: translate("Me"),
  );

  late final Map<MessageKey, MessageBody> _messages = {};

  MessageKey _currentKey = MessageKey('', -2); // -2 is invalid value
  late bool _isShowCMSidePage = false;

  Map<MessageKey, MessageBody> get messages => _messages;

  MessageKey get currentKey => _currentKey;

  bool get isShowCMSidePage => _isShowCMSidePage;

  void setOverlayState(BlockableOverlayState blockableOverlayState) {
    _blockableOverlayState = blockableOverlayState;

    _blockableOverlayState.addMiddleBlockedListener((v) {
      if (!v) {
        isWindowFocus.value = false;
        if (isWindowFocus.value) {
          isWindowFocus.toggle();
        }
      }
    });
  }

  final WeakReference<FFI> parent;

  late final SessionID sessionId;
  late FocusNode inputNode;

  ChatModel(this.parent) {
    sessionId = parent.target!.sessionId;
    inputNode = FocusNode(
      onKey: (_, event) {
        bool isShiftPressed = event.isKeyPressed(LogicalKeyboardKey.shiftLeft);
        bool isEnterPressed = event.isKeyPressed(LogicalKeyboardKey.enter);

        // don't send empty messages
        if (isEnterPressed && isEnterPressed && textController.text.isEmpty) {
          return KeyEventResult.handled;
        }

        if (isEnterPressed && !isShiftPressed) {
          final ChatMessage message = ChatMessage(
            text: textController.text,
            user: me,
            createdAt: DateTime.now(),
          );
          send(message);
          textController.clear();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
    );
  }

  ChatUser? get currentUser => _messages[_currentKey]?.chatUser;

  showChatIconOverlay({Offset offset = const Offset(200, 50)}) {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
    }
    // mobile check navigationBar
    final bar = navigationBarKey.currentWidget;
    if (bar != null) {
      if ((bar as BottomNavigationBar).currentIndex == 1) {
        return;
      }
    }

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;

    final overlay = OverlayEntry(builder: (context) {
      return DraggableFloatWidget(
        config: DraggableFloatWidgetBaseConfig(
          initPositionYInTop: false,
          initPositionYMarginBorder: 100,
          borderTopContainTopBar: true,
        ),
        child: FloatingActionButton(
          onPressed: () {
            if (chatWindowOverlayEntry == null) {
              showChatWindowOverlay();
            } else {
              hideChatWindowOverlay();
            }
          },
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: SvgPicture.asset('assets/chat2.svg'),
        ),
      );
    });
    overlayState.insert(overlay);
    chatIconOverlayEntry = overlay;
  }

  hideChatIconOverlay() {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
      chatIconOverlayEntry = null;
    }
  }

  showChatWindowOverlay({Offset? chatInitPos}) {
    if (chatWindowOverlayEntry != null) return;
    isWindowFocus.value = true;
    _blockableOverlayState.setMiddleBlocked(true);

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;
    if (isMobile &&
        !gFFI.chatModel.currentKey.isOut && // not in remote page
        gFFI.chatModel.latestReceivedKey != null) {
      gFFI.chatModel.changeCurrentKey(gFFI.chatModel.latestReceivedKey!);
      gFFI.chatModel.mobileClearClientUnread(gFFI.chatModel.currentKey.connId);
    }
    final overlay = OverlayEntry(builder: (context) {
      return Listener(
          onPointerDown: (_) {
            if (!isWindowFocus.value) {
              isWindowFocus.value = true;
              _blockableOverlayState.setMiddleBlocked(true);
            }
          },
          child: DraggableChatWindow(
              position: chatInitPos ?? chatWindowPosition,
              width: 250,
              height: 350,
              chatModel: this));
    });
    overlayState.insert(overlay);
    chatWindowOverlayEntry = overlay;
    requestChatInputFocus();
  }

  hideChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) {
      _blockableOverlayState.setMiddleBlocked(false);
      chatWindowOverlayEntry!.remove();
      chatWindowOverlayEntry = null;
      return;
    }
  }

  _isChatOverlayHide() =>
      ((!(isDesktop || isWebDesktop) && chatIconOverlayEntry == null) ||
          chatWindowOverlayEntry == null);

  toggleChatOverlay({Offset? chatInitPos}) {
    if (_isChatOverlayHide()) {
      gFFI.invokeMethod("enable_soft_keyboard", true);
      if (!(isDesktop || isWebDesktop)) {
        showChatIconOverlay();
      }
      showChatWindowOverlay(chatInitPos: chatInitPos);
    } else {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  hideChatOverlay() {
    if (!_isChatOverlayHide()) {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  showChatPage(MessageKey key) async {
    if (isDesktop) {
      if (isConnManager) {
        if (!_isShowCMSidePage) {
          await toggleCMChatPage(key);
        }
      } else {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    } else {
      if (key.connId == clientModeID) {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    }
  }

  toggleCMChatPage(MessageKey key) async {
    if (gFFI.chatModel.currentKey != key) {
      gFFI.chatModel.changeCurrentKey(key);
    }
    await toggleCMSidePage();
  }

  toggleCMFilePage() async {
    await toggleCMSidePage();
  }

  toggleCMSidePage() async {}

  changeCurrentKey(MessageKey key) {}

  receive(int id, String text) async {}

  send(ChatMessage message) {
    String trimmedText = message.text.trim();
    if (trimmedText.isEmpty) {
      return;
    }
    message.text = trimmedText;
    insertMessage(_currentKey, message);
    if (_currentKey.connId == clientModeID && parent.target != null) {
      bind.sessionSendChat(sessionId: sessionId, text: message.text);
    } else {
      bind.cmSendChat(connId: _currentKey.connId, msg: message.text);
    }

    notifyListeners();
    inputNode.requestFocus();
  }

  insertMessage(MessageKey key, ChatMessage message) {
    updateConnIdOfKey(key);
    if (!_messages.containsKey(key)) {
      _messages[key] = MessageBody(message.user, []);
    }
    _messages[key]?.insert(message);
  }

  updateConnIdOfKey(MessageKey key) {
    if (_messages.keys
            .toList()
            .firstWhereOrNull((e) => e == key && e.connId != key.connId) !=
        null) {
      final value = _messages.remove(key);
      if (value != null) {
        _messages[key] = value;
      }
    }
    if (_currentKey == key || _currentKey.peerId.isEmpty) {
      _currentKey = key; // hash != assign
    }
  }

  void mobileUpdateUnreadSum() {}

  void mobileClearClientUnread(int id) {}

  close() {
    hideChatIconOverlay();
    hideChatWindowOverlay();
    notifyListeners();
  }

  resetClientMode() {
    _messages[clientModeID]?.clear();
  }

  void requestChatInputFocus() {
    Timer(Duration(milliseconds: 100), () {
      if (inputNode.hasListeners && inputNode.canRequestFocus) {
        inputNode.requestFocus();
      }
    });
  }

  void onVoiceCallWaiting() {
    _voiceCallStatus.value = VoiceCallStatus.waitingForResponse;
  }

  void onVoiceCallStarted() {
    _voiceCallStatus.value = VoiceCallStatus.connected;
    if (isAndroid) {
      parent.target?.invokeMethod("on_voice_call_started");
    }
  }

  void onVoiceCallClosed(String reason) {
    _voiceCallStatus.value = VoiceCallStatus.notStarted;
    if (isAndroid) {
      // We can always invoke "on_voice_call_closed"
      // no matter if the `_voiceCallStatus` was `VoiceCallStatus.notStarted` or not.
      parent.target?.invokeMethod("on_voice_call_closed");
    }
  }

  void onVoiceCallIncoming() {
    if (isConnManager) {
      _voiceCallStatus.value = VoiceCallStatus.incoming;
    }
  }

  void closeVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: sessionId);
  }
}

enum VoiceCallStatus {
  notStarted,
  waitingForResponse,
  connected,
  // Connection manager only.
  incoming
}
