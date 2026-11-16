import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

TextStyle _t(double size, Color color, [FontWeight w = FontWeight.w400]) =>
    GoogleFonts.getFont(currentFontFamily, fontSize: size, color: color, fontWeight: w);

/// Android Settings: one column, grouped cards, 60 dp rows. Each row leads
/// with a flat 36 dp tile (violet 16 %, pale-violet icon) - flat on purpose,
/// no gradient. Rows with a switch toggle on tap anywhere; rows that open a
/// page show a chevron. Use inside a ListView with 16 dp side padding.
class MobileSettingsGroup extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;
  const MobileSettingsGroup({super.key, this.title, this.footer, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(height: 1, indent: 66, color: kHairline));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(title!.toUpperCase(),
                  style: _t(12, kMuted2, FontWeight.w700).copyWith(letterSpacing: 0.9)),
            ),
          Container(
            decoration: BoxDecoration(
              color: kRaisedColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kHairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(footer!, style: _t(12, kMuted3)),
            ),
        ],
      ),
    );
  }
}

class MobileSettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool? switchValue; // non-null => shows a switch
  final ValueChanged<bool>? onSwitch;

  const MobileSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.switchValue,
    this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final isSwitch = switchValue != null;
    return InkWell(
      onTap: isSwitch ? () => onSwitch?.call(!switchValue!) : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kBrandColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: kVioletPale),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _t(15, kTextColor, FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(13, kMuted2)),
                    ],
                  ],
                ),
              ),
              if (isSwitch)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Switch(value: switchValue!, onChanged: onSwitch),
                )
              else
                const SizedBox(
                  width: 40,
                  height: 48,
                  child: Icon(Icons.chevron_right_rounded, size: 22, color: kMuted3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
