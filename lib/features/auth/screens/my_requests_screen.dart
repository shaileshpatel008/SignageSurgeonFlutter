import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

// Every trackable service collection lives here — add a new entry when a
// new service (e.g. Cleaning) gets its own request flow + tracking screen.
// Nothing else in this file needs to change to support it.
const List<String> _trackableCollections = [
  'repair_requests',
  'rebranding_requests',
  'new_signage_requests',
  'cleaning_requests',
  'amc_requests',
];

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _tabs = ['All', 'In Progress', 'Completed'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: Column(
            children: [
              // ── HEADER ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: AppColors.navy, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'My Requests',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── TABS ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: AppColors.navy,
                  unselectedLabelColor: AppColors.grey,
                  labelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // ── TAB VIEWS ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: List.generate(_tabs.length, (tabIndex) {
                    if (user == null) {
                      return _emptyState('Please log in to view requests');
                    }
                    return _MergedRequestsList(uid: user.uid, tabIndex: tabIndex, tabs: _tabs);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.receipt_long_outlined,
                color: AppColors.greyLight, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppColors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your requests will appear here',
            style: TextStyle(color: AppColors.greyLight, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Subscribes to `service_requests` plus every collection in
/// [_trackableCollections], merges + sorts + filters them, and renders the
/// list. Uses manual stream subscriptions (not nested StreamBuilders) so
/// adding a new service collection is a one-line change at the top of this
/// file instead of another level of nesting.
class _MergedRequestsList extends StatefulWidget {
  final String uid;
  final int tabIndex;
  final List<String> tabs;

  const _MergedRequestsList({required this.uid, required this.tabIndex, required this.tabs});

  @override
  State<_MergedRequestsList> createState() => _MergedRequestsListState();
}

class _MergedRequestsListState extends State<_MergedRequestsList> {
  final Map<String, List<Map<String, dynamic>>> _bySource = {};
  final List<StreamSubscription<QuerySnapshot>> _subs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscribeAll();
  }

  void _subscribeAll() {
    final sources = <String, String>{
      'service_requests': 'service',
      for (final c in _trackableCollections) c: c.replaceAll('_requests', ''),
    };

    int pending = sources.length;

    for (final entry in sources.entries) {
      final collection = entry.key;
      final sourceKey = entry.value;
      final sub = FirebaseFirestore.instance
          .collection(collection)
          .where('userId', isEqualTo: widget.uid)
          .snapshots()
          .listen((snap) {
        _bySource[sourceKey] = snap.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, '_docId': doc.id, '_source': sourceKey})
            .toList();
        if (_loading) {
          pending--;
          if (pending <= 0 && mounted) setState(() => _loading = false);
        } else if (mounted) {
          setState(() {});
        }
      });
      _subs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String _unifiedStatus(Map<String, dynamic> data, String source) {
    if (source == 'amc') {
      final phase = data['amcPhase'] as String?;
      if (phase == 'amc_confirmed' || phase == 'audit_proposal_rejected') return 'completed';
      return 'in_progress';
    }
    if (source == 'cleaning') {
      final phase = data['cleaningPhase'] as String?;
      if (phase == 'rejected') return 'completed';
      if (phase != 'active') return 'in_progress'; // awaiting quotation/approval/payment
      final stage = data['trackingStage'] as String?;
      return stage == 'completed' ? 'completed' : 'in_progress';
    }
    if (source != 'service') {
      final stage = data['trackingStage'] as String?;
      if (stage == 'completed' || stage == 'quotation_rejected') return 'completed';
      return 'in_progress';
    }
    return (data['status'] as String?) ?? 'pending';
  }

  DateTime? _sortDate(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
    }

    final combined = <Map<String, dynamic>>[];
    for (final list in _bySource.values) {
      combined.addAll(list);
    }

    combined.sort((a, b) {
      final da = _sortDate(a);
      final db = _sortDate(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final filter = widget.tabIndex == 1 ? 'in_progress' : widget.tabIndex == 2 ? 'completed' : 'all';
    final filtered = filter == 'all'
        ? combined
        : combined.where((d) => _unifiedStatus(d, d['_source']) == filter).toList();

    if (filtered.isEmpty) {
      return _emptyState(widget.tabIndex == 0 ? 'No requests yet' : 'No ${widget.tabs[widget.tabIndex].toLowerCase()} requests');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _requestCard(context, filtered[i], _unifiedStatus),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.receipt_long_outlined, color: AppColors.greyLight, size: 34),
          ),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          const Text('Your requests will appear here', style: TextStyle(color: AppColors.greyLight, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Shared card rendering + lookup helpers (top-level so both classes above can use them) ──

Color _statusColor(String status) {
  switch (status) {
    case 'completed':
      return AppColors.green;
    case 'cancelled':
      return AppColors.red;
    case 'in_progress':
      return const Color(0xFF4B7BFF);
    default:
      return AppColors.yellowDark;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'in_progress':
      return 'In Progress';
    case 'pending':
      return 'Pending';
    default:
      return status;
  }
}

IconData _serviceIcon(String serviceType) {
  switch (serviceType) {
    case 'repair':
      return Icons.build_outlined;
    case 'rebranding':
      return Icons.brush_outlined;
    case 'new_signage':
      return Icons.add_business_outlined;
    case 'cleaning':
      return Icons.cleaning_services_outlined;
    case 'amc':
      return Icons.shield_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

Color _serviceColor(String serviceType) {
  switch (serviceType) {
    case 'repair':
      return AppColors.red;
    case 'rebranding':
      return AppColors.yellow;
    case 'new_signage':
      return AppColors.navy;
    case 'cleaning':
      return const Color(0xFF9B6BFF); // distinct purple — was colliding with new_signage's navy before
    case 'amc':
      return AppColors.yellowDark;
    default:
      return AppColors.grey;
  }
}

String _formatDate(dynamic timestamp) {
  if (timestamp == null) return '';
  final dt = (timestamp as Timestamp).toDate();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

String _legacyServiceLabel(String serviceType) {
  switch (serviceType) {
    case 'repairing':
      return 'Signage Repairing';
    case 'rebranding':
      return 'Rebranding';
    case 'new_signage':
      return 'New Signage';
    case 'cleaning':
      return 'Signage Cleaning';
    case 'amc':
      return 'Signage AMC';
    default:
      return serviceType;
  }
}

// Category name shown as a small badge on each card, so it's clear which of
// the 6 services a request belongs to even when its specific product/type
// name (e.g. "Rooftop Signage") doesn't make that obvious on its own.
String _categoryLabel(String source) {
  switch (source) {
    case 'repair':
      return 'Repairing';
    case 'rebranding':
      return 'Rebranding';
    case 'new_signage':
      return 'New Signage';
    case 'cleaning':
      return 'Signage Cleaning';
    case 'amc':
      return 'Signage AMC';
    default:
      return '';
  }
}

String _cardLabel(Map<String, dynamic> data, String source) {
  switch (source) {
    case 'repair':
      return data['signageType'] as String? ?? 'Signage Repairing';
    case 'rebranding':
      return data['rebrandingRequirement'] as String? ?? 'Rebranding Request';
    case 'new_signage':
      return data['signageRequirement'] as String? ?? 'New Signage Request';
    case 'cleaning':
      return data['signageType'] as String? ?? 'Signage Cleaning';
    case 'amc':
      return data['requirementType'] as String? ?? 'Signage AMC';
    default:
      return _legacyServiceLabel((data['serviceType'] as String?) ?? '');
  }
}

Widget _requestCard(BuildContext context, Map<String, dynamic> data, String Function(Map<String, dynamic>, String) unifiedStatusFn) {
  final source = data['_source'] as String;
  final docId = data['_docId'] as String;
  final isTrackable = source != 'service';
  final serviceType = source == 'service' ? (data['serviceType'] ?? '') : source;
  final status = unifiedStatusFn(data, source);
  final statusColor = _statusColor(status);
  final serviceColor = _serviceColor(serviceType);
  final date = _formatDate(data['createdAt']);
  final description = isTrackable ? (data['issueDescription'] ?? '') : (data['description'] ?? '');
  final address = isTrackable
      ? ((data['location'] as Map<String, dynamic>?)?['address'] ?? '')
      : (data['address'] ?? data['location'] ?? '');
  final label = _cardLabel(data, source);
  final categoryLabel = _categoryLabel(source);

  return GestureDetector(
    onTap: isTrackable
        ? () => source == 'cleaning'
            ? Navigator.pushNamed(context, AppRoutes.cleaningTracking, arguments: docId)
            : source == 'amc'
                ? Navigator.pushNamed(context, AppRoutes.amcTracking, arguments: docId)
                : Navigator.pushNamed(context, AppRoutes.requestTracking,
                    arguments: {'collection': '${source}_requests', 'requestId': docId})
        : null,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(12)),
                  child: Icon(_serviceIcon(serviceType), color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (categoryLabel.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: serviceColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            categoryLabel.toUpperCase(),
                            style: TextStyle(color: serviceColor, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.bold)),
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(date, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.13), borderRadius: BorderRadius.circular(8)),
                  child: Text(_statusLabel(status), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.greyLight, height: 1),
              const SizedBox(height: 12),
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, height: 1.5)),
            ],
            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.grey, size: 13),
                  const SizedBox(width: 4),
                  Expanded(child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.grey, fontSize: 11))),
                ],
              ),
            ],
            if (isTrackable) ...[
              const SizedBox(height: 10),
              Row(
                children: const [
                  Spacer(),
                  Text('Tap to track', style: TextStyle(color: AppColors.yellowDark, fontSize: 11, fontWeight: FontWeight.w700)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, color: AppColors.yellowDark, size: 10),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}