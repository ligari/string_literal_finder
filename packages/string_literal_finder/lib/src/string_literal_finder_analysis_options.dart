import 'dart:convert';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

class StringLiteralFinderAnalysisOptions {
  StringLiteralFinderAnalysisOptions({
    required this.excludeGlobs,
    required this.ignoreConstructorCalls,
    required this.ignoreMethodInvocationTargets,
    required this.ignoreStringLiteralRegexes,
    this.debug = false,
  });

  static final _logger = Logger('string_literal_finder_analysis_options');

  static StringLiteralFinderAnalysisOptions loadFromYaml(String yamlSource) {
    final yaml =
        json.decode(json.encode(loadYaml(yamlSource))) as Map<String, dynamic>;
    final options = yaml['string_literal_finder'] as Map<String, dynamic>?;
    final excludeGlobs =
        options?['exclude_globs'] as List<dynamic>? ?? <dynamic>[];
    final ignoreConstructorCalls =
        options?['ignore_constructor_calls'] as List<dynamic>? ?? <dynamic>[];
    final ignoreMethodInvocationTargets =
        options?['ignore_method_invocation_targets'] as List<dynamic>? ??
            <dynamic>[];
    final ignoreStringLiteralRegexes =
        options?['ignore_string_literal_regexes'] as List<dynamic>? ??
            <dynamic>[];
    final debug = options?['debug'] as bool? ?? false;
    return StringLiteralFinderAnalysisOptions(
      excludeGlobs: excludeGlobs.cast<String>().map((e) => Glob(e)).toList(),
      ignoreConstructorCalls: ignoreConstructorCalls
          .cast<String>()
          .map((e) => Uri.parse(e))
          .toList(),
      ignoreMethodInvocationTargets: ignoreMethodInvocationTargets
          .cast<String>()
          .map((e) => Uri.parse(e))
          .toList(),
      ignoreStringLiteralRegexes: ignoreStringLiteralRegexes
          .cast<String>()
          .map((e) => RegExp(e))
          .toList(),
      debug: debug,
    );
  }

  final List<Uri> ignoreConstructorCalls;
  final List<Uri> ignoreMethodInvocationTargets;
  final List<RegExp> ignoreStringLiteralRegexes;
  final List<Glob> excludeGlobs;
  final bool debug;

  bool isExcluded(String path) {
    return excludeGlobs.any((glob) => glob.matches(path));
  }

  static StringLiteralFinderAnalysisOptions fromAnalysisContext(
    AnalysisContext context,
  ) {
    final optionsPath = context.contextRoot.optionsFile;
    _logger.info('Loading analysis options.');
    final exists = optionsPath?.exists ?? false;
    if (!exists || optionsPath == null) {
      _logger.warning('Unable to resolve optionsFile.');
      return StringLiteralFinderAnalysisOptions(
        excludeGlobs: [],
        ignoreConstructorCalls: [],
        ignoreMethodInvocationTargets: [],
        ignoreStringLiteralRegexes: [],
      );
    }
    return StringLiteralFinderAnalysisOptions.loadFromYaml(
        optionsPath.readAsStringSync());
  }
}
