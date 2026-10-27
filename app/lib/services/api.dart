import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  Api(this.baseUrl, {this.token});
  String baseUrl;
  String? token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      body = {'error': r.statusCode == 429 ? 'too_many_requests' : 'server_error_${r.statusCode}'};
    }
    if (r.statusCode >= 400) throw ApiException(body['error']?.toString() ?? 'error');
    return body;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decode(r);
  }

  Future<bool> otpRequired() async {
    final r = await http.get(Uri.parse('$baseUrl/config')).timeout(const Duration(seconds: 20));
    return _decode(r)['otpRequired'] != false;
  }

  Future<void> requestOtp(String phone) => _post('/auth/request-otp', {'phone': phone});

  /// Returns {token, phone}
  Future<Map<String, dynamic>> verifyOtp(String phone, String code) =>
      _post('/auth/verify-otp', {'phone': phone, 'code': code});

  Future<Set<String>> matchContacts(List<String> hashes) async {
    final res = await _post('/contacts/match', {'hashes': hashes});
    return (res['matched'] as List).cast<String>().toSet();
  }

  Future<List<Map<String, dynamic>>> iceServers() async {
    final r = await http
        .get(Uri.parse('$baseUrl/ice'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final res = _decode(r);
    return (res['iceServers'] as List).cast<Map<String, dynamic>>();
  }
}
