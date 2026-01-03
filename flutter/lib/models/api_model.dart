import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

final dio = Dio();

class Api {
  final String baseURL;

  Api(this.baseURL);

  Future<void> publish(
      {required String id,
      required Map<String, dynamic> event}) async {
    await dio.post('$baseURL/channels/$id', data: event).catchError((error) {
      debugPrint("publish event failed $error");
    });
  }

  Future<void> updateDevice(
      {required String id, String? osPassword, String? osUsername}) async {
    final data = {};
    if (osPassword != null) data['osPassword'] = osPassword;
    if (osUsername != null) data['osUsername'] = osUsername;

    await dio.patch('$baseURL/devices/$id', data: data).catchError((error) {
      debugPrint("update device failed $error");
    });
  }
}
