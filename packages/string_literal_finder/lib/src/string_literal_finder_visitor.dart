import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:logging/logging.dart';
import 'package:source_gen/source_gen.dart';
import 'package:string_literal_finder/src/found_string_literal.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('string_literal_finder_visitor');

class StringLiteralFinderVisitor<R> extends GeneralizingAstVisitor<R> {
  StringLiteralFinderVisitor({
    required this.filePath,
    required this.unit,
    required this.foundStringLiteral,
    required List<Uri> ignoreConstructorCalls,
    required List<Uri> ignoreMethodInvocationTargets,
    required List<RegExp> ignoreStringLiteralRegexes,
  })  : lineInfo = unit.lineInfo,
        ignoreConstructorCallTypeCheckers = [
          ...defaultIgnoreConstructorCallTypeCheckers,
          ...ignoreConstructorCalls.map((e) => TypeChecker.fromUrl(e)),
        ],
        ignoreMethodInvocationTargetTypeCheckers = [
          ...defaultIgnoreMethodInvocationTargetTypeCheckers,
          ...ignoreMethodInvocationTargets.map((e) => TypeChecker.fromUrl(e)),
        ],
        ignoreStringLiteralRegexes = [
          ...ignoreStringLiteralRegexes,
        ];

  // Database expressions
  static const TypeChecker nonNlsChecker = TypeChecker.fromRuntime(NonNlsArg);
  final List<RegExp> ignoreStringLiteralRegexes;
  static const List<RegExp> defaultIgnoreStringLiteralRegexes = [];
  final List<TypeChecker> ignoreMethodInvocationTargetTypeCheckers;
  static const List<TypeChecker> defaultIgnoreMethodInvocationTargetTypeCheckers = [
    TypeChecker.fromRuntime(Logger),
  ];
  final List<TypeChecker> ignoreConstructorCallTypeCheckers;
  static const List<TypeChecker> defaultIgnoreConstructorCallTypeCheckers = [
    TypeChecker.fromRuntime(Uri),
    TypeChecker.fromRuntime(RegExp),
    TypeChecker.fromUrl('package:flutter/src/widgets/image.dart#Image'),
    TypeChecker.fromUrl('package:flutter/src/painting/image_resolution.dart#AssetImage'),
    TypeChecker.fromUrl('package:flutter/src/widgets/navigator.dart#RouteSettings'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#ValueKey'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#UniqueKey'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#LocalKey'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#Key'),
    TypeChecker.fromUrl('package:flutter/src/services/platform_channel.dart#MethodChannel'),
    TypeChecker.fromRuntime(StateError),
    TypeChecker.fromRuntime(Logger),
    TypeChecker.fromRuntime(Exception),
    TypeChecker.fromRuntime(Error),
  ];

  final String filePath;
  final CompilationUnit unit;
  final LineInfo? lineInfo;
  final void Function(FoundStringLiteral foundStringLiteral) foundStringLiteral;

  @override
  R? visitStringLiteral(StringLiteral node) {
//    final previous = node.findPrevious(node.beginToken);
    final parent = node.parent;
    final pp = node.parent?.parent;

    if (_shouldIgnore(node)) {
      return null;
    }

    final lineInfo = unit.lineInfo;
    final begin = node.beginToken.charOffset;
    final end = node.endToken.charEnd;
    final loc = lineInfo.getLocation(begin);
    final locEnd = lineInfo.getLocation(end);

    final next = node.endToken.next;
    final nextNext = next?.next;
    _logger.finest('''Found string literal (${loc.lineNumber}:${loc.columnNumber}) $node
         - parent: $parent (${parent.runtimeType})
         - parentParent: $pp (${pp.runtimeType} / ${pp!.parent?.runtimeType})
         - next: $next
         - nextNext: $nextNext 
         - precedingComments: ${node.beginToken.precedingComments}''');
    foundStringLiteral(FoundStringLiteral(
      filePath: filePath,
      loc: loc,
      locEnd: locEnd,
      stringValue: node.stringValue,
      stringLiteral: node,
    ));
    return super.visitStringLiteral(node);
  }

  bool _checkArgumentAnnotation(
      ArgumentList argumentList, ExecutableElement? executableElement, Expression nodeChildChild) {
    final argPos = argumentList.arguments.indexOf(nodeChildChild);
    assert(argPos != -1);
    final arg = argumentList.arguments[argPos];
    ParameterElement param;
    if (arg is NamedExpression) {
      param = executableElement!.parameters.firstWhere(
          (element) => element.isNamed && element.name == arg.name.label.name,
          orElse: () => throw StateError('Unable to find parameter of name ${arg.name.label} for '
              '$executableElement'));
    } else if (executableElement != null) {
      param = executableElement.parameters[argPos];
      assert(param.isPositional);
    } else {
      return false;
    }
    if (nonNlsChecker.hasAnnotationOf(param)) {
//      _logger.finest('XX Argument is annotated with NonNls.');
      return true;
    }
    return false;
  }

  bool _shouldIgnore(StringLiteral origNode) {
    AstNode? node = origNode;
    AstNode? nodeChild;
    AstNode? nodeChildChild;

    // test regular expressions
    if (origNode.stringValue != null) {
      for (final regExp in ignoreStringLiteralRegexes) {
        if (regExp.hasMatch(origNode.stringValue!)) {
          return true;
        }
      }
    }

    // iterate up the tree
    for (; node != null; nodeChildChild = nodeChild, nodeChild = node, node = node.parent) {
      try {
        // ignore imports, parts and partOf
        if (node is ImportDirective || node is PartDirective || node is PartOfDirective) {
          return true;
        }
        // ignore annotations
        if (node is Annotation) {
          _logger.finest('Ignoring annotation parameters $node');
          return true;
        }
        // ignore annotated class fields
        if (node is ClassDeclaration) {
          if (nonNlsChecker.hasAnnotationOf(node.declaredElement!)) {
            if (nodeChild is FieldDeclaration) {
              if (nodeChild.isStatic) {
                return true;
              }
            }
          }
        }
        // ignore annotated indexed expressions
        if (node is IndexExpression) {
          final target = node.realTarget;
          if (target is SimpleIdentifier) {
            try {
              if (nonNlsChecker.hasAnnotationOf(target.staticElement!)) {
                return true;
              }
            } catch (e, stackTrace) {
              _logger.warning(
                  'Unable to check annotation for $origNode at $filePath', e, stackTrace);
            }
          }
        }
        // ignore annotated enum constants
        if (node is EnumConstantArguments) {
          final constantDeclaration = node.parent as EnumConstantDeclaration;
          final constructor = constantDeclaration.constructorElement;
          if (_checkArgumentAnnotation(
            node.argumentList,
            constructor,
            nodeChildChild as Expression,
          )) {
            return true;
          }
        }
        // check constructor calls to ignore
        if (node is InstanceCreationExpression) {
          assert(nodeChild == node.argumentList);
          // ignore annotated constructor calls
          if (_checkArgumentAnnotation(node.argumentList, node.constructorName.staticElement,
              nodeChildChild as Expression)) {
            return true;
          }
          // ignore constructor calls to types
          for (final ignoredConstructorCall in ignoreConstructorCallTypeCheckers) {
            if (ignoredConstructorCall.isAssignableFrom(node.staticType!.element2!)) {
              return true;
            }
          }
        }
        // ignore annotated variable declarations
        if (node is VariableDeclaration) {
          final element = node.declaredElement;
          if (element != null && nonNlsChecker.hasAnnotationOf(element)) {
            return true;
          }
        }
        // ignore annotated function parameters
        if (node is FormalParameter) {
          final element = node.declaredElement;
          if (element != null && nonNlsChecker.hasAnnotationOf(element)) {
            return true;
          }
        }
        // check method calls to ignore
        if (node is MethodInvocation) {
          // ignore selected method calls
          // TODO: ignoring selected methodName doesn't work
          if (node.methodName.name == 'debugPrint') {
            return true;
          }
          // ignore function calls if the invoked functions argument is annotated
          if (nodeChildChild is! Expression) {
            _logger.warning('not an expression. $nodeChildChild ($node)');
          } else if (
              // check if `nodeChildChild` is actually a full argument.
              // this can happen with sub expressions like
              // myFunc('string'.split('').join('')); where
              // `string'.split('')` will not be found in the parent expression.
              node.argumentList.arguments.contains(nodeChildChild) &&
                  // check if the argument is annotated
                  _checkArgumentAnnotation(node.argumentList,
                      node.methodName.staticElement as ExecutableElement?, nodeChildChild)) {
            return true;
          }
          // ignore method calls to types
          if (node.target != null) {
            // ignore calls to types
            if (node.target!.staticType == null) {
              _logger.warning('Unable to resolve staticType for ${node.target}');
            } else {
              final staticType = node.target!.staticType!;
              for (final checker in ignoreMethodInvocationTargetTypeCheckers) {
                if (checker.isAssignableFromType(staticType)) {
                  return true;
                }
              }
            }
          }
        }
        // ignore annotated function or method declarations
        if (node is FunctionDeclaration || node is MethodDeclaration) {
          if (node is Declaration) {
            if (nonNlsChecker.hasAnnotationOf(node.declaredElement!)) {
              return true;
            }
          }
        }
      } catch (e, stackTrace) {
        final loc = lineInfo!.getLocation(origNode.offset);
        _logger.severe('Error while analysing node $origNode at $filePath $loc', e, stackTrace);
      }
    }
    // ignore line-end comments
    final lineNumber = lineInfo!.getLocation(origNode.end).lineNumber;
    var nextToken = origNode.endToken.next;
    while (nextToken != null && lineInfo!.getLocation(nextToken.offset).lineNumber == lineNumber) {
      nextToken = nextToken.next;
    }
    final comment = nextToken!.precedingComments;
    if (comment != null && lineInfo!.getLocation(comment.offset).lineNumber == lineNumber) {
      if (comment.value().contains('NON-NLS')) {
        return true;
      }
    }
    // else don't ignore
    return false;
  }
}
