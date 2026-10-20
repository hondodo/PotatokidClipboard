import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class DioLogInterceptor extends PrettyDioLogger {
  DioLogInterceptor({
    super.requestHeader = true,
    super.requestBody = true,
    super.responseBody = false,
    super.responseHeader = true,
    super.error = true,
    super.compact = true,
    super.maxWidth = 90,
  });
}
