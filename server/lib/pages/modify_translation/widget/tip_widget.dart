import 'package:flutter/material.dart';

class TipController extends ChangeNotifier {
  String _tipString = '';
  String get tipString => _tipString;
  void setTipString(String value) {
    _tipString = value;
    notifyListeners();
  }
}

class TipWidget extends StatefulWidget {
  const TipWidget({super.key, required this.controller});
  final TipController controller;

  @override
  State<TipWidget> createState() => _TipWidgetState();
}

class _TipWidgetState extends State<TipWidget> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTipChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTipChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onTipChanged() {
    if (widget.controller.tipString.isNotEmpty) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 100, // 距离顶部的距离
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.controller.tipString,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    // 返回一个空的widget，因为提示通过Overlay显示
    return const SizedBox.shrink();
  }
}
