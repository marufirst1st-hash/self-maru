import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AwsS3Service {
  // 빌드 시 dart-define으로 주입: --dart-define=AWS_ACCESS_KEY=... --dart-define=AWS_SECRET_KEY=...
  static const String _accessKeyId = String.fromEnvironment('AWS_ACCESS_KEY', defaultValue: '');
  static const String _secretAccessKey = String.fromEnvironment('AWS_SECRET_KEY', defaultValue: '');
  static const String _region = String.fromEnvironment('AWS_REGION', defaultValue: 'ap-northeast-2');
  static const String _bucketName = String.fromEnvironment('AWS_BUCKET', defaultValue: 'floor-measure-storage');
  static const String _baseUrl = 'https://$_bucketName.s3.$_region.amazonaws.com';

  // 파일 업로드 (사진 or DXF)
  Future<String?> uploadFile({
    required String projectId,
    required String fileName,
    required Uint8List fileBytes,
    required String contentType,
    required S3FileType fileType,
  }) async {
    final folder = fileType == S3FileType.photo ? 'photos' : 'drawings';
    final s3Key = 'projects/$projectId/$folder/$fileName';
    final url = '$_baseUrl/$s3Key';

    try {
      final now = DateTime.now().toUtc();
      final dateStamp = DateFormat('yyyyMMdd').format(now);
      final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);

      // 헤더 구성
      final headers = {
        'Content-Type': contentType,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': _sha256Hex(fileBytes),
        'Host': '$_bucketName.s3.$_region.amazonaws.com',
      };

      // AWS Signature V4
      final signature = _buildSignature(
        method: 'PUT',
        s3Key: s3Key,
        headers: headers,
        payload: fileBytes,
        dateStamp: dateStamp,
        amzDate: amzDate,
      );

      final authHeader = 'AWS4-HMAC-SHA256 '
          'Credential=$_accessKeyId/$dateStamp/$_region/s3/aws4_request, '
          'SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, '
          'Signature=$signature';

      final response = await http.put(
        Uri.parse(url),
        headers: {
          ...headers,
          'Authorization': authHeader,
        },
        body: fileBytes,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return url;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // AWS Signature V4 생성
  String _buildSignature({
    required String method,
    required String s3Key,
    required Map<String, String> headers,
    required Uint8List payload,
    required String dateStamp,
    required String amzDate,
  }) {
    final payloadHash = _sha256Hex(payload);

    // 1. Canonical Request
    final sortedHeaders = Map.fromEntries(
      headers.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
    final canonicalHeaders = '${sortedHeaders.entries.map((e) => '${e.key.toLowerCase()}:${e.value.trim()}').join('\n')}\n';
    final signedHeaders = sortedHeaders.keys.map((k) => k.toLowerCase()).join(';');

    final canonicalRequest = [
      method,
      '/$s3Key',
      '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    // 2. String to Sign
    final credentialScope = '$dateStamp/$_region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      _sha256Hex(utf8.encode(canonicalRequest)),
    ].join('\n');

    // 3. Signing Key
    final signingKey = _getSigningKey(dateStamp);

    // 4. Signature
    return _hmacSha256Hex(signingKey, stringToSign);
  }

  List<int> _getSigningKey(String dateStamp) {
    final kDate = _hmacSha256Bytes(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256Bytes(kDate, _region);
    final kService = _hmacSha256Bytes(kRegion, 's3');
    return _hmacSha256Bytes(kService, 'aws4_request');
  }

  String _sha256Hex(List<int> data) {
    return sha256.convert(data).toString();
  }

  List<int> _hmacSha256Bytes(List<int> key, String message) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(message)).bytes;
  }

  String _hmacSha256Hex(List<int> key, String message) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(message)).toString();
  }

  // 업로드 결과 URL 반환
  String getFileUrl(String projectId, String fileName, S3FileType fileType) {
    final folder = fileType == S3FileType.photo ? 'photos' : 'drawings';
    return '$_baseUrl/projects/$projectId/$folder/$fileName';
  }

  // 파일 삭제
  Future<bool> deleteFile(String s3Key) async {
    final url = '$_baseUrl/$s3Key';
    try {
      final now = DateTime.now().toUtc();
      final dateStamp = DateFormat('yyyyMMdd').format(now);
      final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);

      final emptyHash = _sha256Hex(Uint8List(0));
      final headers = {
        'x-amz-date': amzDate,
        'x-amz-content-sha256': emptyHash,
        'Host': '$_bucketName.s3.$_region.amazonaws.com',
      };

      final signature = _buildSignature(
        method: 'DELETE',
        s3Key: s3Key,
        headers: headers,
        payload: Uint8List(0),
        dateStamp: dateStamp,
        amzDate: amzDate,
      );

      final credentialScope = '$dateStamp/$_region/s3/aws4_request';
      final authHeader = 'AWS4-HMAC-SHA256 '
          'Credential=$_accessKeyId/$credentialScope, '
          'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
          'Signature=$signature';

      final response = await http.delete(
        Uri.parse(url),
        headers: {...headers, 'Authorization': authHeader},
      );

      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }
}

enum S3FileType { photo, drawing }

// 업로드 결과 모델
class S3UploadResult {
  final bool success;
  final String? url;
  final String? error;

  const S3UploadResult({
    required this.success,
    this.url,
    this.error,
  });
}
