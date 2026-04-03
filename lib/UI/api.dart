import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiService {
  static const String _baseUrl =
      'https://zigmaglobal.in/uniceil/attendance';

  Uri _buildUri(String endpoint, [Map<String, String>? queryParameters]) {
    return Uri.parse(
      '$_baseUrl/$endpoint',
    ).replace(queryParameters: queryParameters);
  }

  String normalizeEmployeeId(String rawValue) {
    final digitsOnly = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }

    final parsed = int.tryParse(digitsOnly);
    if (parsed == null) {
      return digitsOnly;
    }

    return parsed.toString().padLeft(3, '0');
  }

  Future<Map<String, dynamic>> registerAttendee({
    required String employeeName,
    required String designation,
    required String reportingOfficer,
    required String phoneNumber,
    XFile? profileImage,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _buildUri('register_employee.php'),
    );
    request.fields['employee_name'] = employeeName.trim();
    request.fields['designation'] = designation.trim();
    request.fields['reporting_officer'] = reportingOfficer.trim();
    request.fields['phone_number'] = phoneNumber.trim();

    if (profileImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'source_image',
          profileImage.path,
          filename: path.basename(profileImage.path),
        ),
      );
    }

    return _sendMultipartRequest(request);
  }

  Future<Map<String, dynamic>> lookupAttendee(String employeeId) async {
    final normalizedId = normalizeEmployeeId(employeeId);
    final response = await http.get(
      _buildUri('employee_lookup.php', {'employee_id': normalizedId}),
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> submitPunch({
    required String employeeId,
    required XFile captureImage,
    required double latitude,
    required double longitude,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _buildUri('manual_attendance.php'),
    );
    request.fields['employee_id'] = normalizeEmployeeId(employeeId);
    request.fields['latitude'] = latitude.toStringAsFixed(7);
    request.fields['longitude'] = longitude.toStringAsFixed(7);
    request.files.add(
      await http.MultipartFile.fromPath(
        'source_image',
        captureImage.path,
        filename: path.basename(captureImage.path),
      ),
    );

    return _sendMultipartRequest(request);
  }

  Future<Map<String, dynamic>> fetchReport({
    DateTime? date,
    bool allDates = false,
  }) async {
    final query = <String, String>{};
    if (allDates) {
      query['scope'] = 'all';
    } else {
      final selectedDate = date ?? DateTime.now();
      query['date'] = _formatDate(selectedDate);
    }

    final response = await http.get(_buildUri('mark_attendance.php', query));
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _sendMultipartRequest(
    http.MultipartRequest request,
  ) async {
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final dynamic decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);

    if (decoded is! Map) {
      throw ApiException('Unexpected server response.');
    }

    final payload = Map<String, dynamic>.from(decoded);
    final message = payload['message']?.toString();

    if (response.statusCode >= 400 || payload['success'] == false) {
      throw ApiException(message ?? 'Request failed.');
    }

    return payload;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
