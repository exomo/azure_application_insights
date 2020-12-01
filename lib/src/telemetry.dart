import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';
import 'context.dart';
import 'serialization.dart';

/// A base class for all types of telemetry items.
@immutable
abstract class TelemetryItem {
  /// When the telemetry was created.
  DateTime get timestamp;

  /// The Application Insights envelope name used when transmitting telemetry of this type.
  String get envelopeName;

  /// Gets a serialized representation of this telemetry.
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  });
}

/// Represents a custom event telemetry item in Application Insights.
@immutable
class EventTelemetryItem implements TelemetryItem {
  /// Creates an instance of [EventTelemetryItem] with the specified [name].
  EventTelemetryItem({
    @required this.name,
    this.additionalProperties,
    DateTime timestamp,
  })  : assert(name != null),
        assert(timestamp == null || timestamp.isUtc),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get envelopeName => 'AppEvents';

  @override
  final DateTime timestamp;

  /// The name of the event.
  final String name;

  /// Any additional properties to submit with the telemetry.
  final Map<String, Object> additionalProperties;

  @override
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  }) =>
      <String, dynamic>{
        'baseType': 'EventData',
        'baseData': <String, dynamic>{
          'ver': 2,
          'name': name,
          'properties': <String, dynamic>{
            ...context.properties,
            ...?additionalProperties,
          }
        },
      };
}

/// Represents an exception telemetry item in Application Insights.
@immutable
class ExceptionTelemetryItem implements TelemetryItem {
  /// Creates an instance of [ExceptionTelemetryItem] with the specified [severity] and [error].
  ///
  /// If no [problemId] is provided, one will be generated based on the [error] and [stackTrace] (if any) provided.
  ExceptionTelemetryItem({
    @required this.severity,
    @required this.error,
    this.stackTrace,
    this.problemId,
    this.additionalProperties,
    DateTime timestamp,
  })  : assert(severity != null),
        assert(error != null),
        assert(timestamp == null || timestamp.isUtc),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get envelopeName => 'AppExceptions';

  @override
  final DateTime timestamp;

  /// The severity of the exception.
  final Severity severity;

  /// The underlying error.
  final Object error;

  /// The [StackTrace] captured when the error occurred, which may be `null`.
  final StackTrace stackTrace;

  /// An identifier to associate multiple instances of this error which, if `null`, will cause a problem ID to be
  /// generated based on the [error] and [stackTrace] (if any) provided.
  final String problemId;

  /// Any additional properties to submit with the telemetry.
  final Map<String, Object> additionalProperties;

  @override
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  }) {
    final trace = stackTrace == null ? null : Trace.parse(stackTrace.toString());
    return <String, dynamic>{
      'baseType': 'ExceptionData',
      'baseData': <String, dynamic>{
        'ver': 2,
        'severityLevel': severity.intValue,
        'exceptions': [
          _getErrorDataMap(trace),
        ],
        'problemId': problemId ?? _generateProblemId(trace),
        'properties': <String, dynamic>{
          ...context.properties,
          ...?additionalProperties,
        },
      },
    };
  }

  String _generateProblemId(Trace trace) {
    // Make a best effort at disambiguating errors by using the error message and the first frame from any available stack trace.
    final code = '$error${trace == null || trace.frames.isEmpty ? '' : trace.frames[0].toString()}';
    final codeBytes = utf8.encode(code);
    final hash = sha1.convert(codeBytes);
    final result = hash.toString();
    return result;
  }

  Map<String, dynamic> _getErrorDataMap(Trace trace) => <String, dynamic>{
        'typeName': error.runtimeType.toString(),
        'message': error.toString(),
        'hasFullStack': trace != null,
        if (trace != null && trace.frames.isNotEmpty)
          'parsedStack': trace.frames
              .asMap()
              .entries
              .map((e) => <String, dynamic>{
                    'level': e.key,
                    'method': e.value.member,
                    'assembly': e.value.package,
                    'fileName': e.value.location,
                    'line': e.value.line,
                  })
              .toList(growable: false),
      };
}

/// Represents a page view telemetry item in Application Insights.
@immutable
class PageViewTelemetryItem implements TelemetryItem {
  /// Creates an instance of [PageViewTelemetryItem] with the specified [name].
  PageViewTelemetryItem({
    @required this.name,
    this.id,
    this.duration,
    this.url,
    this.additionalProperties,
    DateTime timestamp,
  })  : assert(name != null),
        assert(timestamp == null || timestamp.isUtc),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get envelopeName => 'AppPageViews';

  @override
  final DateTime timestamp;

  /// The page name.
  final String name;

  /// How long the page took to display, which may be `null`.
  final Duration duration;

  /// The ID of the page, which may be `null`.
  final String id;

  /// The URL of the page, which may be `null`.
  final String url;

  /// Any additional properties to submit with the telemetry.
  final Map<String, Object> additionalProperties;

  @override
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  }) =>
      <String, dynamic>{
        'baseType': 'PageViewData',
        'baseData': <String, dynamic>{
          'ver': 2,
          'name': name,
          if (id != null) 'id': id,
          if (duration != null) 'duration': formatDurationForDotNet(duration),
          if (url != null) 'url': url,
          'properties': <String, dynamic>{
            ...context.properties,
            ...?additionalProperties,
          }
        },
      };
}

/// Represents a request telemetry item in Application Insights.
@immutable
class RequestTelemetryItem implements TelemetryItem {
  /// Creates an instance of [RequestTelemetryItem] with the specified [id], [duration], and [responseCode].
  RequestTelemetryItem({
    @required this.id,
    @required this.duration,
    @required this.responseCode,
    this.source,
    this.name,
    this.success,
    this.url,
    this.additionalProperties,
    DateTime timestamp,
  })  : assert(id != null),
        assert(duration != null),
        assert(responseCode != null),
        assert(timestamp == null || timestamp.isUtc),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get envelopeName => 'AppRequests';

  @override
  final DateTime timestamp;

  /// The ID of the request.
  final String id;

  /// The duration of the request.
  final Duration duration;

  /// The response code for the request.
  final String responseCode;

  /// The source of the request, which may be `null`.
  final String source;

  /// The name of the request, which may be `null`.
  final String name;

  /// Whether the request was successful or not, which may be `null`.
  final bool success;

  /// The URL of the request, which may be `null`.
  final String url;

  /// Any additional properties to submit with the telemetry.
  final Map<String, Object> additionalProperties;

  @override
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  }) =>
      <String, dynamic>{
        'baseType': 'RequestData',
        'baseData': <String, dynamic>{
          'ver': 2,
          'id': id,
          'duration': formatDurationForDotNet(duration),
          'responseCode': responseCode,
          if (source != null) 'source': source,
          if (name != null) 'name': name,
          if (success != null) 'success': success,
          if (url != null) 'url': url,
          'properties': <String, dynamic>{
            ...context.properties,
            ...?additionalProperties,
          }
        },
      };
}

/// Represents a trace telemetry item in Application Insights.
@immutable
class TraceTelemetryItem implements TelemetryItem {
  /// Creates an instance of [TraceTelemetryItem] with the specified [severity] and [message].
  TraceTelemetryItem({
    @required this.severity,
    @required this.message,
    this.additionalProperties,
    DateTime timestamp,
  })  : assert(severity != null),
        assert(message != null),
        assert(timestamp == null || timestamp.isUtc),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get envelopeName => 'AppTraces';

  @override
  final DateTime timestamp;

  /// The trace severity.
  final Severity severity;

  /// The trace message.
  final String message;

  /// Any additional properties to submit with the telemetry.
  final Map<String, Object> additionalProperties;

  @override
  Map<String, dynamic> serialize({
    @required TelemetryContext context,
  }) =>
      <String, dynamic>{
        'baseType': 'MessageData',
        'baseData': <String, dynamic>{
          'ver': 2,
          'severityLevel': severity.intValue,
          'message': message,
          'properties': <String, dynamic>{
            ...context.properties,
            ...?additionalProperties,
          }
        },
      };
}

/// Defines severity levels for relevant telemetry items.
enum Severity {
  /// Verbose severity.
  verbose,

  /// Informational severity.
  information,

  /// Warning severity.
  warning,

  /// Error severity.
  error,

  /// Critical severity.
  critical,
}

extension _SeverityExtensions on Severity {
  int get intValue {
    switch (this) {
      case Severity.verbose:
        return 0;
      case Severity.information:
        return 1;
      case Severity.warning:
        return 2;
      case Severity.error:
        return 3;
      case Severity.critical:
        return 4;
      default:
        throw UnsupportedError('Unsupported value: $this');
    }
  }
}
