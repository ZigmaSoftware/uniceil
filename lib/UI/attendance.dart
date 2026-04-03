import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wpe_summit_attendance_2026/UI/api.dart';

// ── Colour tokens ──────────────────────────────────────────────────────────
const _navy = Color(0xFF0B1F3A);
const _bg = Color(0xFFF2F5FA);
const _surface = Colors.white;
const _textPrimary = Color(0xFF0B1F3A);
const _textSecondary = Color(0xFF6B7C93);
const _inGreen = Color(0xFF0A7A3E);
const _inGreenBg = Color(0xFFE6F7EE);
const _outBlue = Color(0xFF1055A8);
const _absentGray = Color(0xFF8898AA);
const _absentBg = Color(0xFFF0F3F7);
const _warningAmber = Color(0xFFB45309);
const _warningBg = Color(0xFFFFF8E6);

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  final _apiService = ApiService();
  late TabController _dateTabController;

  bool _allDates = false;
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  String? _errorMessage;
  Map<String, dynamic>? _reportPayload;
  String _statusFilter = 'all';

  // 0 = Today, 1 = Pick date, 2 = All dates
  int _dateMode = 0;

  @override
  void initState() {
    super.initState();
    _dateTabController = TabController(length: 3, vsync: this);
    _dateTabController.addListener(() {
      if (_dateTabController.indexIsChanging) return;
      _onDateModeChanged(_dateTabController.index);
    });
    _loadReport();
  }

  @override
  void dispose() {
    _dateTabController.dispose();
    super.dispose();
  }

  void _onDateModeChanged(int index) async {
    if (index == 1) {
      // pick date
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2024),
        lastDate: DateTime(2035),
        builder: (ctx, child) => Theme(
          data: Theme.of(
            ctx,
          ).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
          child: child!,
        ),
      );
      if (picked == null) {
        // revert tab
        _dateTabController.index = _dateMode;
        return;
      }
      setState(() {
        _dateMode = 1;
        _selectedDate = picked;
        _allDates = false;
        if (_statusFilter == 'Absent') _statusFilter = 'all';
      });
    } else if (index == 2) {
      setState(() {
        _dateMode = 2;
        _allDates = true;
        if (_statusFilter == 'Absent') _statusFilter = 'all';
      });
    } else {
      setState(() {
        _dateMode = 0;
        _allDates = false;
        _selectedDate = DateTime.now();
      });
    }
    await _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.fetchReport(
        date: _selectedDate,
        allDates: _allDates,
      );
      if (!mounted) return;
      setState(() => _reportPayload = response);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _records {
    final raw = _reportPayload?['records'];
    if (raw is! List) return [];
    return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _records;
    return _records.where((r) {
      final s = (r['attendance_status'] ?? 'Absent').toString();
      return s == _statusFilter;
    }).toList();
  }

  Map<String, dynamic> get _summary {
    final raw = _reportPayload?['summary'];
    if (raw is! Map) return {};
    return Map<String, dynamic>.from(raw);
  }

  int _summaryColumnCount(double maxWidth, int itemCount) {
    if (maxWidth >= 720) return itemCount;
    if (maxWidth >= 520 && itemCount <= 3) return itemCount;
    return 2;
  }

  double _summaryCardWidth(double maxWidth, int itemCount) {
    const spacing = 10.0;
    final columns = _summaryColumnCount(maxWidth, itemCount);
    return (maxWidth - (spacing * (columns - 1))) / columns;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildDateSelector()),
          SliverToBoxAdapter(child: _buildSummaryRow()),
          SliverToBoxAdapter(child: _buildFilterRow()),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
        ],
        body: _buildBody(),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      expandedHeight: 70,
      actions: [
        IconButton(
          onPressed: _loadReport,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 60, 16),
        title: const Text(
          'Attendance Reports',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Container(
          color: _navy,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
              child: Text(
                '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      color: _navy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _dateTabController,
          isScrollable: true,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: _navy,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.8),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.all(4),
          tabs: [
            const Tab(text: 'Today'),
            Tab(
              text: _dateMode == 1
                  ? DateFormat('dd MMM').format(_selectedDate)
                  : 'Pick Date',
            ),
            const Tab(text: 'All Dates'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    final s = _summary;
    final isLoading = _isLoading;

    final total =
        (_allDates ? s['total_records'] : s['registered_count'])?.toString() ??
        '—';
    final present = (s['present_count'] ?? 0).toString();
    final noOut = (s['no_out_punch_count'] ?? 0).toString();
    final absent = _allDates ? null : (s['absent_count'] ?? 0).toString();
    final cards = <Widget>[
      _SummaryCard(
        label: _allDates ? 'Total Records' : 'Registered',
        value: total,
        icon: Icons.groups_rounded,
        color: _navy,
        bgColor: const Color(0xFFE8EEF6),
      ),
      _SummaryCard(
        label: 'Present',
        value: present,
        icon: Icons.check_circle_rounded,
        color: _inGreen,
        bgColor: _inGreenBg,
      ),
      _SummaryCard(
        label: 'No Out Punch',
        value: noOut,
        icon: Icons.schedule_rounded,
        color: _warningAmber,
        bgColor: _warningBg,
      ),
      if (absent != null)
        _SummaryCard(
          label: 'Absent',
          value: absent,
          icon: Icons.cancel_rounded,
          color: _absentGray,
          bgColor: _absentBg,
        ),
    ];

    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = _summaryCardWidth(
            constraints.maxWidth,
            cards.length,
          );

          if (isLoading) {
            return _buildSummarySkeleton(constraints.maxWidth, cards.length);
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummarySkeleton(double maxWidth, int itemCount) {
    final cardWidth = _summaryCardWidth(maxWidth, itemCount);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(
        itemCount,
        (_) => Container(
          width: cardWidth,
          height: 82,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = [
      ('all', 'All'),
      ('Present', 'Present'),
      ('No out punch', 'No Out Punch'),
      if (!_allDates) ('Absent', 'Absent'),
    ];

    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...filters.map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: f.$2,
                  selected: _statusFilter == f.$1,
                  onTap: () {
                    if (_statusFilter != f.$1) {
                      setState(() => _statusFilter = f.$1);
                    }
                  },
                  count: _statusFilter == f.$1 ? _filtered.length : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }

    if (_errorMessage != null) {
      return _ErrorView(message: _errorMessage!, onRetry: _loadReport);
    }

    final records = _filtered;

    if (records.isEmpty) {
      return _EmptyView(filter: _statusFilter);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) =>
          _RecordTile(record: records[i], showDate: _allDates),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _navy : _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _navy : const Color(0xFFDDE3ED),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : _textSecondary,
              ),
            ),
            if (count != null && selected) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Record Tile ───────────────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.showDate});

  final Map<String, dynamic> record;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final status = (record['attendance_status'] ?? 'Absent').toString();

    final (statusColor, statusBg, statusIcon) = switch (status) {
      'Present' => (_inGreen, _inGreenBg, Icons.check_circle_rounded),
      'No out punch' => (_warningAmber, _warningBg, Icons.schedule_rounded),
      _ => (_absentGray, _absentBg, Icons.cancel_rounded),
    };

    final name = (record['employee_name'] ?? '').toString();
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    final hasInPhoto = (record['punch_in_image_url'] ?? '')
        .toString()
        .isNotEmpty;
    final hasOutPhoto = (record['punch_out_image_url'] ?? '')
        .toString()
        .isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                _TileAvatar(
                  initials: initials,
                  color: statusColor,
                  bgColor: statusBg,
                ),
                const SizedBox(width: 12),
                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                          _StatusBadge(
                            label: status,
                            color: statusColor,
                            bgColor: statusBg,
                            icon: statusIcon,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _MetaChip(
                            label: record['employee_code'].toString(),
                            color: _navy,
                          ),
                          if ((record['designation'] ?? '')
                              .toString()
                              .isNotEmpty)
                            _MetaChip(
                              label: record['designation'].toString(),
                              color: _textSecondary,
                            ),
                          if (showDate &&
                              (record['report_date'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                            _MetaChip(
                              label: record['report_date'].toString(),
                              color: _textSecondary,
                            ),
                        ],
                      ),
                      if ((record['reporting_officer'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Reports to: ${record['reporting_officer']}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Punch time row
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFD),
              border: Border(top: BorderSide(color: Color(0xFFEDF0F7))),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _PunchStat(
                  label: 'IN',
                  value: (record['punch_in_label'] ?? '—').toString(),
                  color: _inGreen,
                  icon: Icons.login_rounded,
                ),
                _VerticalDivider(),
                _PunchStat(
                  label: 'OUT',
                  value: (record['punch_out_label'] ?? '—').toString(),
                  color: _outBlue,
                  icon: Icons.logout_rounded,
                ),
                _VerticalDivider(),
                _PunchStat(
                  label: 'Hours',
                  value: (record['total_hours'] ?? '—').toString(),
                  color: _navy,
                  icon: Icons.timer_outlined,
                ),
                if (hasInPhoto || hasOutPhoto) ...[
                  _VerticalDivider(),
                  _PhotoIndicators(hasIn: hasInPhoto, hasOut: hasOutPhoto),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileAvatar extends StatelessWidget {
  const _TileAvatar({
    required this.initials,
    required this.color,
    required this.bgColor,
  });

  final String initials;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PunchStat extends StatelessWidget {
  const _PunchStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDash = value == '—' || value == '--';

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: isDash ? _textSecondary : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isDash ? _textSecondary : color,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: isDash ? const Color(0xFFCDD3DC) : _textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFFEDF0F7),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _PhotoIndicators extends StatelessWidget {
  const _PhotoIndicators({required this.hasIn, required this.hasOut});

  final bool hasIn;
  final bool hasOut;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_camera_rounded, size: 11, color: _textSecondary),
              SizedBox(width: 4),
              Text(
                'Photos',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PhotoDot(active: hasIn, label: 'IN'),
              const SizedBox(width: 4),
              _PhotoDot(active: hasOut, label: 'OUT'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoDot extends StatelessWidget {
  const _PhotoDot({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: active ? _inGreenBg : const Color(0xFFF0F3F7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: active ? _inGreen : const Color(0xFFCDD3DC),
        ),
      ),
    );
  }
}

// ── State views ───────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFD32F2F),
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to load report',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F3F7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: _textSecondary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No records found',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filter == 'all'
                  ? 'No attendance records for the selected date.'
                  : 'No attendees match the "$filter" filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
