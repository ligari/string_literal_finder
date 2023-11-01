import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// Information about a string literal found in dart code.
class FoundStringLiteral {
  FoundStringLiteral({
    required this.filePath,
    required this.loc,
    required this.locEnd,
    required this.stringValue,
    required this.stringLiteral,
  });

  /// absolute file path to the file in which the string literal was found.
  final String filePath;

  /// line/column of the beginning of the string literal.
  final CharacterLocation loc;

  /// line/column of the end of the string literal.
  final CharacterLocation locEnd;

  /// The actual value of the string, better to use [stringLiteral].
  final String? stringValue;

  /// The string literal from the analyser.
  final StringLiteral stringLiteral;

  int get charOffset => stringLiteral.beginToken.charOffset;

  int get charEnd => stringLiteral.endToken.charEnd;

  int get charLength => charEnd - charOffset;
}
