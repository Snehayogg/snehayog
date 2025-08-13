/// Centralized exception handling for the application
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => 'AppException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Network-related exceptions
class NetworkException extends AppException {
  const NetworkException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class TimeoutException extends AppException {
  const TimeoutException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class ServerException extends AppException {
  const ServerException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

/// Authentication-related exceptions
class AuthenticationException extends AppException {
  const AuthenticationException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

/// Data-related exceptions
class DataException extends AppException {
  const DataException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class ValidationException extends AppException {
  const ValidationException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

/// File-related exceptions
class FileException extends AppException {
  const FileException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class FileSizeException extends AppException {
  const FileSizeException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}

class FileTypeException extends AppException {
  const FileTypeException(String message, {String? code, dynamic details})
      : super(message, code: code, details: details);
}
