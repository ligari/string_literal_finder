import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/found_string_literal.dart';
import 'package:string_literal_finder/src/string_literal_finder_analysis_options.dart';
import 'package:string_literal_finder/src/string_literal_finder_visitor.dart';

final _logger = Logger('string_literal_finder');

/// The main finder class which will analyse all
/// dart files in the given [basePath] and look for string literals.
/// Some literals will be (smartly) ignored which should not be localized.
class StringLiteralFinder {
  StringLiteralFinder({
    required this.basePath,
  });

  /// Base path of the library.
  final String basePath;

  final List<FoundStringLiteral> foundStringLiterals = [];
  final Set<String> filesSkipped = <String>{};
  final Set<String> filesAnalyzed = <String>{};

  /// Starts the analyser and returns information about the found
  /// string literals.
  Future<List<FoundStringLiteral>> start() async {
    _logger.fine('Starting analysis.');
    final collection = AnalysisContextCollection(includedPaths: [basePath]);
    _logger.finer('Finding contexts.');
    for (final context in collection.contexts) {
      // find analysis options
      final analysisOptions = StringLiteralFinderAnalysisOptions.fromAnalysisContext(context);

      // resolve root
      final root = context.contextRoot.root.path;

      for (final filePath in context.contextRoot.analyzedFiles()) {
        // only include dart files & check excluded files
        var relative = '';
        relative = path.relative(filePath, from: root);
        if (analysisOptions.isExcluded(relative) || !filePath.endsWith('.dart')) {
          filesSkipped.add(filePath);
          continue;
        }
        // else analyze
        filesAnalyzed.add(filePath);
        await _analyzeSingleFile(
          context: context,
          filePath: filePath,
          options: analysisOptions,
        );
      }
    }

    // logging
    _logger.info('Found ${foundStringLiterals.length} literals:');
    for (final f in foundStringLiterals) {
      final relative = path.relative(f.filePath, from: basePath);
      _logger.info('$relative:${f.loc} ${f.stringLiteral}');
    }

    return foundStringLiterals;
  }

  Future<void> _analyzeSingleFile({
    required AnalysisContext context,
    required String filePath,
    required StringLiteralFinderAnalysisOptions options,
  }) async {
    _logger.fine('analyzing $filePath');
    final result = await context.currentSession.getResolvedUnit(filePath);
    if (result is! ResolvedUnitResult) {
      throw StateError('Did not resolve to valid unit.');
    }
    final unit = result.unit;
    final visitor = StringLiteralFinderVisitor<dynamic>(
        filePath: filePath,
        unit: unit,
        ignoreConstructorCalls: options.ignoreConstructorCalls,
        ignoreMethodInvocationTargets: options.ignoreMethodInvocationTargets,
        ignoreStringLiteralRegexes: options.ignoreStringLiteralRegexes,
        foundStringLiteral: (foundStringLiteral) {
          foundStringLiterals.add(foundStringLiteral);
        });
    unit.visitChildren(visitor);
  }
}
