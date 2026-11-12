import 'dart:math' as math;

/// Result of parsing an AutoEq / Equalizer APO text file onto the 10-band
/// graphic equalizer. Nothing in the text is ever executed: it is only read
/// line by line for numbers.
class EqImportResult {
  final List<double>? gains;
  final double preampDb;
  final List<String> warnings;
  final String? error;

  const EqImportResult({
    this.gains,
    this.preampDb = 0.0,
    this.warnings = const [],
    this.error,
  });
}

class EqImport {
  static const List<double> bandHz = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
  ];
  static const double maxDb = 12.0;
  static const Set<String> _supported = {'PK', 'PEQ', 'LSC', 'HSC', 'LS', 'HS'};

  static int _nearest(double hz) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < bandHz.length; i++) {
      final d = (math.log(hz) - math.log(bandHz[i])).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  static double _clamp(double db, List<String> warnings, String where) {
    if (db > maxDb || db < -maxDb) {
      warnings.add('$where: ${db.toStringAsFixed(1)} dB clamped to ±12 dB.');
      return db.clamp(-maxDb, maxDb).toDouble();
    }
    return db;
  }

  static EqImportResult parse(String text) {
    final gains = List<double>.filled(10, 0.0);
    final warnings = <String>[];
    var preamp = 0.0;
    var filters = 0;
    final numRe = RegExp(r'-?\d+(?:\.\d+)?');
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.startsWith('preamp:')) {
        final m = numRe.firstMatch(line.substring(7));
        if (m != null) {
          preamp = _clamp(double.parse(m.group(0)!), warnings, 'Preamp');
        }
        continue;
      }
      if (lower.startsWith('graphiceq:')) {
        for (final pair in line.substring(10).split(';')) {
          final nums = numRe.allMatches(pair).map((m) => double.parse(m.group(0)!)).toList();
          if (nums.length < 2 || nums[0] <= 0) continue;
          final i = _nearest(nums[0]);
          // Keep the strongest point that lands on a band.
          final g = _clamp(nums[1], warnings, '${nums[0].round()} Hz');
          if (g.abs() > gains[i].abs()) gains[i] = g;
          filters++;
        }
        continue;
      }
      if (lower.startsWith('filter')) {
        final m = RegExp(
                r'Filter\s*\d*\s*:\s*(ON|OFF)\s+(\w+)\s+Fc\s+(\d+(?:\.\d+)?)\s*Hz(?:\s+Gain\s+(-?\d+(?:\.\d+)?)\s*dB)?',
                caseSensitive: false)
            .firstMatch(line);
        if (m == null) {
          return EqImportResult(error: 'Could not read this line: "$line"');
        }
        final type = m.group(2)!.toUpperCase();
        if (!_supported.contains(type)) {
          return EqImportResult(
              error: 'Unsupported filter type "$type". Nothing was imported.');
        }
        if (m.group(1)!.toUpperCase() == 'OFF') continue;
        final hz = double.parse(m.group(3)!);
        final db = double.tryParse(m.group(4) ?? '0') ?? 0.0;
        final i = _nearest(hz);
        if (type != 'PK' && type != 'PEQ') {
          warnings.add(
              '$type at ${hz.round()} Hz approximated as a band at ${bandHz[i].round()} Hz.');
        }
        gains[i] = _clamp(gains[i] + db, warnings, '${hz.round()} Hz');
        filters++;
        continue;
      }
      return EqImportResult(error: 'Unknown line: "$line". Nothing was imported.');
    }
    if (filters == 0) {
      return const EqImportResult(error: 'No filters found in that text.');
    }
    return EqImportResult(gains: gains, preampDb: preamp, warnings: warnings);
  }
}
