import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Pulse design kit: palette, type scale, chips, cards, covers, play
/// buttons, hover wrappers and the floating toast - shared by the Pulse
/// screen and any future board-styled page.
class PC {
  static const bg = Color(0xFF0B0F14);
  static const card = Color(0xFF111723);
  static const raised = Color(0xFF161F2E);
  static const tooltip = Color(0xFF1B2335);
  static const border = Color(0x14FFFFFF);
  static const borderSoft = Color(0x0DFFFFFF);
  static const text = Color(0xFFE8E8F0);
  static const textSoft = Color(0xFFB4BBCB);
  static const muted = Color(0xFF9AA3B5);
  static const faint = Color(0xFF8B93A7);
  static const violet = Color(0xFF7C3AED);
  static const violetLight = Color(0xFFA78BFA);
  static const violetPale = Color(0xFFC4B5FD);
  static const cyan = Color(0xFF00D4FF);
  static const cyanText = Color(0xFF67E8F9);
  static const pink = Color(0xFFFF6B9D);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const amberDeep = Color(0xFFF59E0B);
  static const rose = Color(0xFFBE123C);
  static const blue = Color(0xFF60A5FA);
  static const blueDeep = Color(0xFF1E3A8A);
  static const teal = Color(0xFF2DD4BF);
  static const tealDeep = Color(0xFF0E7490);
  static const indigo = Color(0xFF312E81);
  static const plum = Color(0xFF4C1D95);
  static const pinkSoft = Color(0xFFF9A8D4);
  static const greenDeep = Color(0xFF065F46);
}

TextStyle pts(double s,
        {FontWeight w = FontWeight.w400,
        Color c = PC.text,
        double? ls,
        double? h}) =>
    GoogleFonts.inter(
        fontSize: s, fontWeight: w, color: c, letterSpacing: ls, height: h);

String hm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m m';
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')} m';
}

void pToast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(m, style: pts(13, c: PC.text)),
      backgroundColor: PC.raised,
      behavior: SnackBarBehavior.floating,
      width: 420,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: PC.border)),
      duration: const Duration(seconds: 2),
    ));
}

class PChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const PChip(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? PC.violet : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? Colors.transparent : PC.border, width: 1),
          ),
          child: Text(label,
              style: pts(13,
                  w: FontWeight.w600, c: active ? Colors.white : PC.textSoft)),
        ),
      );
}

class PSection extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const PSection(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(text.toUpperCase(),
              style: pts(11, w: FontWeight.w700, c: PC.faint, ls: 1)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

class PPlay extends StatelessWidget {
  final double size;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final bool shadow;
  const PPlay(
      {super.key,
      required this.size,
      required this.onTap,
      this.bg = PC.violet,
      this.fg = Colors.white,
      this.shadow = true});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: shadow
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          child: Icon(Icons.play_arrow_rounded,
              size: size * 0.42, color: fg),
        ),
      );
}

class PCover extends StatelessWidget {
  final double w, h, r;
  final List<Color> colors;
  final Widget? child;
  final bool shadow;
  const PCover(
      {super.key,
      required this.w,
      required this.h,
      required this.colors,
      this.r = 12,
      this.child,
      this.shadow = true});
  @override
  Widget build(BuildContext context) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors),
          borderRadius: BorderRadius.circular(r),
          boxShadow: shadow
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: child,
      );
}

class PTrack extends StatelessWidget {
  final double? width;
  final double h;
  final double value;
  final Color color;
  const PTrack(
      {super.key,
      this.width,
      this.h = 4,
      required this.value,
      this.color = PC.violetLight});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(h / 2)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(h / 2))),
        ),
      );
}

class PHover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool lift;
  const PHover({super.key, required this.child, this.onTap, this.lift = true});
  @override
  State<PHover> createState() => _PHoverState();
}

class _PHoverState extends State<PHover> {
  bool _h = false, _d = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() {
          _h = false;
          _d = false;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _d = true),
          onTapUp: (_) => setState(() => _d = false),
          onTapCancel: () => setState(() => _d = false),
          child: AnimatedScale(
            scale: _d ? 0.98 : (_h && widget.lift ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

class PCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(24)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: PC.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: PC.border)),
        child: child,
      );
}

class PScroll extends StatelessWidget {
  final Widget child;
  const PScroll({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final c = ScrollController();
    return Scrollbar(
      controller: c,
      thickness: 8,
      radius: const Radius.circular(4),
      thumbVisibility: false,
      child: SingleChildScrollView(
          controller: c,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
          child: child),
    );
  }
}
