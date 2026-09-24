import '../../../framework/components/app_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum BaseNetStatusImageType {
  empty,
  cancelled,
  error,
  noNetwork,
}

extension BaseNetStatusImageTypeExtension on BaseNetStatusImageType {
  Widget get image {
    return switch (this) {
      BaseNetStatusImageType.empty => const Icon(Icons.hourglass_empty),
      BaseNetStatusImageType.cancelled => const Icon(Icons.cancel),
      BaseNetStatusImageType.error => const Icon(Icons.error),
      BaseNetStatusImageType.noNetwork => const Icon(Icons.network_check),
    };
  }
}

class BaseNetStatusWidget extends StatefulWidget {
  const BaseNetStatusWidget({
    super.key,
    required this.imageType,
    required this.message,
    this.showRetryButton = false,
    this.onRetry,
    this.boundingColor,
    this.retryButtonText,
    this.backgroundColor,
  });

  final String message;
  final bool showRetryButton;
  final Color? boundingColor;
  final BaseNetStatusImageType imageType;
  final String? retryButtonText;
  final Color? backgroundColor;

  final Function()? onRetry;

  @override
  State<BaseNetStatusWidget> createState() => _BaseNetStatusWidget();
}

class _BaseNetStatusWidget extends State<BaseNetStatusWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(Object context) {
    String message = widget.message;

    var image = widget.imageType.image;
    var text = Text(
      message,
      maxLines: null,
      textAlign: TextAlign.center,
    );
    List<Widget> children = [
      image,
      const SizedBox(
        height: 16,
      ),
      if (message.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star),
          Flexible(child: text),
          const Icon(Icons.star),
        ]),
    ];
    if (widget.showRetryButton) {
      var retryButton = AppButton(
          onPressed: widget.onRetry,
          child: Text(
            widget.retryButtonText ?? '重试'.tr,
          ));
      children.add(
        const SizedBox(
          height: 16,
        ),
      );
      children.add(SizedBox(
        height: 34,
        child: retryButton,
      ));
    }
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
    Widget background = column;
    if (widget.boundingColor != null) {
      background = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.boundingColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: column,
      );
    }
    var padding = Padding(
      padding: const EdgeInsets.all(32),
      child: background,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: widget.backgroundColor,
          ),
        ),
        Positioned.fill(
          child: Center(child: padding),
        ),
      ],
    );
  }
}
