import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/found_string_literal.dart';
import 'package:string_literal_finder/src/string_literal_finder_visitor.dart';

final _logger = Logger('string_literal_finder');

abstract class ExcludePathChecker {
  const ExcludePathChecker();

  static ExcludePathChecker excludePathCheckerStartsWith(String exclude) =>
      _ExcludePathCheckerImpl(
        predicate: (path) => path.startsWith(exclude),
        description: 'Starts with: $exclude',
      );

  static ExcludePathChecker excludePathCheckerEndsWith(String exclude) =>
      _ExcludePathCheckerImpl(
        predicate: (path) => path.endsWith(exclude),
        description: 'Ends with: $exclude',
      );

  bool shouldExclude(String path);
}

class _ExcludePathCheckerImpl extends ExcludePathChecker {
  const _ExcludePathCheckerImpl(
      {required this.predicate, required this.description});

  final bool Function(String path) predicate;
  final String description;

  @override
  bool shouldExclude(String path) => predicate(path);
}

/// The main finder class which will analyse all
/// dart files in the given [basePath] and look for string literals.
/// Some literals will be (smartly) ignored which should not be localized.
class StringLiteralFinder {
  StringLiteralFinder({
    required this.basePath,
    required this.excludePaths,
  });

  /// Base path of the library.
  final String basePath;

  /// Paths which should be ignored. Usually something like `l10n/' to ignore
  /// the actual translation files.
  final List<ExcludePathChecker> excludePaths;

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
      for (final filePath in context.contextRoot.analyzedFiles()) {
        final relative = path.relative(filePath, from: basePath);
        if (excludePaths
                .where((element) => element.shouldExclude(relative))
                .isNotEmpty ||
            // exclude generated code.
            filePath.endsWith('.g.dart')) {
          filesSkipped.add(filePath);
          continue;
        }
        filesAnalyzed.add(filePath);
        await _analyzeSingleFile(context, filePath);
      }
    }
    _logger.info('Found ${foundStringLiterals.length} literals:');
    for (final f in foundStringLiterals) {
      final relative = path.relative(f.filePath, from: basePath);
      _logger.info('$relative:${f.loc} ${f.stringLiteral}');
    }
    return foundStringLiterals;
  }

  Future<void> _analyzeSingleFile(
      AnalysisContext context, String filePath) async {
    _logger.fine('analyzing $filePath');
    // TODO: parse options
    final result = await context.currentSession.getResolvedUnit(filePath);
    if (result is! ResolvedUnitResult) {
      throw StateError('Did not resolve to valid unit.');
    }
    final unit = result.unit;
    final visitor = StringLiteralFinderVisitor<dynamic>(
        filePath: filePath,
        unit: unit,
        ignoreConstructorCalls: [],
        ignoreMethodInvocationTargets: [],
        ignoreStringLiteralRegexes: [],
        foundStringLiteral: (foundStringLiteral) {
          foundStringLiterals.add(foundStringLiteral);
        });
    unit.visitChildren(visitor);
  }
}
