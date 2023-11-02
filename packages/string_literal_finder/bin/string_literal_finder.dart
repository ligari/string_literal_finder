import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/string_literal_finder.dart';

final _logger = Logger('string_literal_finder');

const executableName = 'string_literal_finder';
const _argPath = 'path';
const _argHelp = 'help';
const _argVerbose = 'verbose';
const _argSilent = 'silent';
const _argMetricsFile = 'metrics-output-file';
const _argAnnotationFileAttest = 'annotations-output-file-attest';
const _argAnnotationPrintGithub = 'annotations-print-github';
const _argAnnotationRoot = 'annotations-path-root';

/// Parse the command line arguments and run the [StringLiteralFinder].
/// This optionally:
/// - writes metrics to a json file
/// - writes the found string literals to an annotations file as taken by
///   https://github.com/Attest/annotations-action/
Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(level: Level.SEVERE);
  final parser = ArgParser()
    ..addOption(
      _argPath,
      mandatory: true,
      abbr: 'p',
      help: 'Base path of your library.',
    )
    ..addOption(_argMetricsFile, abbr: 'm', help: 'File to write json metrics to')
    ..addOption(_argAnnotationFileAttest,
        help: 'File to write annotations to as taken by '
            'https://github.com/Attest/annotations-action/')
    ..addFlag(_argAnnotationPrintGithub,
        help: 'Whether to print annotations usable in GitHub CI as described by '
            'https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions')
    ..addOption(_argAnnotationRoot, help: 'Maks paths relative to the given root directory.')
    ..addFlag(_argVerbose, abbr: 'v')
    ..addFlag(_argSilent, abbr: 's')
    ..addFlag(_argHelp, abbr: 'h', negatable: false);
  try {
    // parse raw arguments
    final results = parser.parse(arguments);

    // show help if requested
    if (results[_argHelp] as bool) {
      throw UsageException('Showing help.', parser.usage);
    }

    // setup logging
    PrintAppender.setupLogging(
        level: results[_argSilent] as bool
            ? Level.SEVERE
            : results[_argVerbose] as bool
                ? Level.ALL
                : Level.FINE);

    // validate arguments
    if (results[_argPath] == null) {
      throw UsageException('Required $_argPath parameter.', parser.usage);
    }

    // parse path argument
    final absolutePath = path.absolute(results[_argPath] as String);

    final stringLiteralFinder = StringLiteralFinder(
      basePath: absolutePath,
    );

    // find string literals
    final foundStringLiterals = await stringLiteralFinder.start();

    // write found string literals to annotations file for attest format
    final annotationsFileAttest = results[_argAnnotationFileAttest] as String?;
    if (annotationsFileAttest != null) {
      await _generateAnnotationsFileAttest(
        annotationsFileAttest,
        foundStringLiterals,
        pathRelativeFrom: results[_argAnnotationRoot] as String?,
      );
    }
    // write found string literals to annotations file for github format
    final annotationsFileGithub = results[_argAnnotationPrintGithub] as bool?;
    if (annotationsFileGithub == true) {
      await _generateAnnotationsGithub(
        foundStringLiterals,
        pathRelativeFrom: results[_argAnnotationRoot] as String?,
      );
    }

    // generate metrics
    final fileCount = foundStringLiterals.map((e) => e.filePath).toSet();
    final nonLiteralFiles = stringLiteralFinder.filesAnalyzed.difference(fileCount);

    // output metrics
    _logger.finest('Files without Literals: $nonLiteralFiles 👍️');
    print('Found ${foundStringLiterals.length} literals in '
        '${fileCount.length} files.');

    // generate json metrics
    final result = {
      'stringLiterals': foundStringLiterals.length,
      'stringLiteralsFiles': fileCount.length,
      'filesAnalyzed': stringLiteralFinder.filesAnalyzed.length,
      'filesSkipped': stringLiteralFinder.filesSkipped.length,
      'filesWithoutLiterals': stringLiteralFinder.filesAnalyzed.length - fileCount.length,
    };
    // encode json metrics
    final jsonMetrics = const JsonEncoder.withIndent('  ').convert(result);

    // output json metrics
    print(jsonMetrics);

    // write json metrics to file
    final metricsFile = results[_argMetricsFile] as String?;
    if (metricsFile != null) {
      await File(metricsFile).writeAsString(jsonMetrics);
    }

    // exit with error code if string literals were found
    if (foundStringLiterals.isNotEmpty) {
      exitCode = 1;
    }
  } on UsageException catch (e, s) {
    _logger.severe('$executableName [arguments]', e, s);
    exitCode = 1;
  } catch (e, s) {
    _logger.severe('Error during analysis.', e, s);
    exitCode = 70;
  }
}

Future<void> _generateAnnotationsFileAttest(
  String file,
  List<FoundStringLiteral> foundStringLiterals, {
  String? pathRelativeFrom,
}) async {
  final resolvePath = (pathRelativeFrom == null)
      ? (String p) => path.absolute(p)
      : (String p) => path.relative(p, from: pathRelativeFrom);

  final annotations = foundStringLiterals
      .map(
        (e) => {
          'message': 'String literal',
          'level': 'notice',
          'path': resolvePath(e.filePath),
          'column': {'start': e.loc.columnNumber, 'end': e.locEnd.columnNumber},
          'line': {'start': e.loc.lineNumber, 'end': e.locEnd.lineNumber},
        },
      )
      .toList();
  await File(file).writeAsString(json.encode(annotations));
}

Future<void> _generateAnnotationsGithub(
  List<FoundStringLiteral> foundStringLiterals, {
  String? pathRelativeFrom,
}) async {
  final resolvePath = (pathRelativeFrom == null)
      ? (String p) => path.absolute(p)
      : (String p) => path.relative(p, from: pathRelativeFrom);

  foundStringLiterals
      .map((e) => "::warning "
          "file=${resolvePath(e.filePath)},"
          "line=${e.loc.lineNumber},"
          "endLine=${e.locEnd.lineNumber},"
          "col=${e.loc.columnNumber},"
          "endColumn=${e.locEnd.columnNumber}::"
          "String literal '${e.stringValue}'")
      .forEach(print);
}
