import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';

class InlineEditFrame extends StatelessWidget {
  const InlineEditFrame({
    super.key,
    required this.child,
    this.borderColor,
    this.borderWidth = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.padding = const EdgeInsets.fromLTRB(4, 4, 4, 6),
  });

  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor ?? AppColors.info,
          width: borderWidth,
        ),
        borderRadius: borderRadius,
      ),
      padding: padding,
      child: child,
    );
  }
}

class InlineEditTextField extends StatelessWidget {
  const InlineEditTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = true,
    this.style,
    this.keyboardType,
    this.inputFormatters,
    this.decoration = const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
    this.borderColor,
    this.borderWidth = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.padding = const EdgeInsets.fromLTRB(4, 4, 4, 6),
    this.minLines = 1,
    this.maxLines = 1,
    this.textAlignVertical,
    this.wrapInFrame = true,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final InputDecoration decoration;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final int? minLines;
  final int? maxLines;
  final TextAlignVertical? textAlignVertical;
  final bool wrapInFrame;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final void Function(PointerDownEvent)? onTapOutside;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: style,
      minLines: minLines,
      maxLines: maxLines,
      textAlignVertical: textAlignVertical ?? TextAlignVertical.center,
      decoration: decoration,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
    );

    if (!wrapInFrame) {
      return field;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: InlineEditFrame(
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderRadius: borderRadius,
        padding: padding,
        child: field,
      ),
    );
  }
}
