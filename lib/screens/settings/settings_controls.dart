part of 'settings_screen.dart';

/// Shared controls for the redesigned Settings pages (Playback, Servers and
/// sources, Audio and EQ). Visual spec from the Settings boards: cards #151B26
/// radius 16, rows separated by 1 px hairlines, title 14/600, helper 13/18,
/// switch 44x26 violet, selected segment violet 18% with violet-light text.

bool get _isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get _isWindowsPlatform => !kIsWeb && Platform.isWindows;
bool get _isAndroidPlatform => defaultTargetPlatform == TargetPlatform.android;

TextStyle _rowTitleStyle() => GoogleFonts.getFont(currentFontFamily,
    color: kTextColor, fontSize: 14, height: 17 / 14, fontWeight: FontWeight.w600);

TextStyle _rowHelperStyle() => GoogleFonts.getFont(currentFontFamily,
    color: kStatusText, fontSize: 13, height: 18 / 13);

/// One settings row: title and helper on the left, a control on the right.
/// Below 560 px the control drops under the text so nothing overflows on
/// phones. A disabled row dims its control and replaces the helper with the
/// reason, so an unavailable setting always says why.
class _ControlRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget trailing;
  final bool enabled;
  final String? disabledReason;
  final bool stackTrailing;

  const _ControlRow({
    required this.label,
    required this.trailing,
    this.description,
    this.enabled = true,
    this.disabledReason,
    this.stackTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    final helper = (!enabled && disabledReason != null)
        ? disabledReason
        : description;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _rowTitleStyle()),
        if (helper != null) ...[
          const SizedBox(height: 3),
          Text(helper, style: _rowHelperStyle()),
        ],
      ],
    );
    final control = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(ignoring: !enabled, child: trailing),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: LayoutBuilder(builder: (context, c) {
          final narrow = stackTrailing || c.maxWidth < 560;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 20),
              control,
            ],
          );
        }),
      ),
    );
  }
}

/// A row whose control is the board switch.
_ControlRow _switchRow({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
  String? description,
  bool enabled = true,
  String? disabledReason,
}) =>
    _ControlRow(
      label: label,
      description: description,
      enabled: enabled,
      disabledReason: disabledReason,
      trailing: _BoardSwitch(value: value, onChanged: onChanged, label: label),
    );

/// A row whose control is a segmented selector.
_ControlRow _segmentedRow({
  required String label,
  required List<(String, String)> options,
  required String value,
  required ValueChanged<String> onChanged,
  String? description,
  bool enabled = true,
  String? disabledReason,
}) =>
    _ControlRow(
      label: label,
      description: description,
      enabled: enabled,
      disabledReason: disabledReason,
      trailing: _SegmentedControl(
          options: options, value: value, onChanged: onChanged),
    );

/// A row whose control is a dropdown pill.
_ControlRow _selectRow({
  required String label,
  required List<(String, String)> options,
  required String value,
  required ValueChanged<String> onChanged,
  String? description,
  bool enabled = true,
  String? disabledReason,
}) =>
    _ControlRow(
      label: label,
      description: description,
      enabled: enabled,
      disabledReason: disabledReason,
      trailing:
          _SelectControl(options: options, value: value, onChanged: onChanged),
    );

/// A row with a slider and a live value label.
_ControlRow _sliderRow({
  required String label,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required String Function(double) format,
  required ValueChanged<double> onCommit,
  String? description,
  bool enabled = true,
  String? disabledReason,
}) =>
    _ControlRow(
      label: label,
      description: description,
      enabled: enabled,
      disabledReason: disabledReason,
      trailing: _SliderControl(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        format: format,
        onCommit: onCommit,
      ),
    );

/// A row whose control is a small button.
_ControlRow _buttonRow({
  required String label,
  required String button,
  required VoidCallback? onTap,
  String? description,
  bool destructive = false,
  bool primary = false,
}) =>
    _ControlRow(
      label: label,
      description: description,
      enabled: onTap != null,
      trailing: _PillButton(
          label: button,
          onTap: onTap,
          destructive: destructive,
          primary: primary),
    );

class _SegmentedControl extends StatelessWidget {
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  /// Options shown but not selectable (dimmed).
  final Set<String> disabledIds;

  const _SegmentedControl(
      {required this.options,
      required this.value,
      required this.onChanged,
      this.disabledIds = const {}});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label) in options)
            ClickRegion(
              onTap: disabledIds.contains(id) ? null : () => onChanged(id),
              child: Semantics(
                button: true,
                selected: id == value,
                label: label,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: ShuroMotion.std,
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: id == value
                        ? kBrandColor.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(label,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: id == value
                              ? kVioletLight
                              : disabledIds.contains(id)
                                  ? kMuted2.withValues(alpha: 0.6)
                                  : kNavText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectControl extends StatelessWidget {
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  const _SelectControl(
      {required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.$1 == value).firstOrNull;
    return PopupMenuButton<String>(
      color: kCardColor,
      tooltip: '',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final (id, label) in options)
          PopupMenuItem<String>(
            value: id,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: id == value
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: kVioletLight)
                      : null,
                ),
                Text(label,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor, fontSize: 13.5)),
              ],
            ),
          ),
      ],
      child: _ValuePill(current?.$2 ?? value),
    );
  }
}

/// Slider that follows the finger locally and commits once on release, so a
/// drag does not write to storage on every tick.
class _SliderControl extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onCommit;
  final double width;

  const _SliderControl({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onCommit,
    this.width = 260,
  });

  @override
  State<_SliderControl> createState() => _SliderControlState();
}

class _SliderControlState extends State<_SliderControl> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final shown = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return SizedBox(
      width: widget.width,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: kBrandColor,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                thumbColor: Colors.white,
                overlayColor: kBrandColor.withValues(alpha: 0.16),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: shown.toDouble(),
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  setState(() => _drag = null);
                  widget.onCommit(v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(widget.format(shown.toDouble()),
                textAlign: TextAlign.right,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kVioletLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool destructive;
  final IconData? icon;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary
        ? Colors.white
        : destructive
            ? const Color(0xFFFCA5A5)
            : kNavText;
    return ClickRegion(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary ? kBrandColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: primary
                ? null
                : Border.all(
                    color: destructive
                        ? const Color(0xFFFCA5A5).withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muted caption row inside a card (long explanations under a control).
class _CaptionRow extends StatelessWidget {
  final String text;
  const _CaptionRow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Text(text, style: _rowHelperStyle()),
      );
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12)),
            ],
          ),
        ),
      );
}

/// A board card holding free-form children (no row dividers), with the
/// 12/600 CAPS label above it. Row-based groups use [_SettingsGroupCard].
class _BoardCardGroup extends StatelessWidget {
  final String? title;
  final Widget? trailingLabel;
  final List<Widget> children;

  const _BoardCardGroup(
      {this.title, this.trailingLabel, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Text(title!, style: _capsLabelStyle()),
                  if (trailingLabel != null) ...[
                    const SizedBox(width: 10),
                    trailingLabel!,
                  ],
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: kRaisedColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _capsLabelStyle() => GoogleFonts.getFont(currentFontFamily,
    color: kMuted2,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1);

/// A hairline between free-form blocks inside a [_BoardCardGroup].
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Divider(
      height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06));
}

/// Inserts hairlines between [rows] (for composite cards).
List<Widget> _withHairlines(List<Widget> rows) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const _Hairline(),
        rows[i],
      ],
    ];

/// Rebuilds [builder] whenever [SettingsExtras] changes.
class _ExtrasScope extends StatefulWidget {
  final Widget Function(BuildContext context, SettingsExtras extras) builder;
  const _ExtrasScope({required this.builder});

  @override
  State<_ExtrasScope> createState() => _ExtrasScopeState();
}

class _ExtrasScopeState extends State<_ExtrasScope> {
  @override
  void initState() {
    super.initState();
    unawaited(SettingsExtras.instance.restore());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SettingsExtras.instance,
        builder: (context, _) =>
            widget.builder(context, SettingsExtras.instance),
      );
}

String _relativeTime(DateTime? at) {
  if (at == null) return 'Not yet this session';
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 45) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String _formatDb(double db, {int digits = 1}) {
  final v = db.toStringAsFixed(digits);
  if (db > 0) return '+$v dB';
  return '${v.replaceFirst('-', '−')} dB';
}
