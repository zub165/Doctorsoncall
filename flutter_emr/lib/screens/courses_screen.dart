import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

import '../services/catalog_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../utils/api_envelope.dart';
import '../widgets/api_access_placeholder.dart';

/// Patient Education (online medical resources) + legacy `GET /api/v1/courses/`.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen>
    with SingleTickerProviderStateMixin {
  late final CatalogApi _api = CatalogApi(widget.apiClient);
  late Future<dynamic> _coursesFuture = _api.courses();
  late final TabController _tabController;

  final _q = TextEditingController();
  final _courseFilter = TextEditingController();
  bool _searching = false;
  String? _searchError;
  List<_EducationItem> _results = const [];

  static const _tabTitles = ['Education', 'Courses', 'Maintenance'];

  static const _quickTopics = [
    'Diabetes',
    'High blood pressure',
    'Asthma',
    'Fever',
    'Heart disease',
    'Pregnancy',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  static String _stripHtml(String raw) {
    return raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static String _medlinePlusSearchUrl(String query) {
    return 'https://medlineplus.gov/search.html?q=${Uri.encodeComponent(query.trim())}';
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _q.dispose();
    _courseFilter.dispose();
    super.dispose();
  }

  void _reloadCourses() {
    setState(() {
      _coursesFuture = _api.courses();
    });
  }

  /// Normalizes `GET /api/v1/courses/` (envelope or plain) into rows + optional API error text.
  (List<Map<String, dynamic>>, String?) _parseCoursesPayload(dynamic data) {
    if (data == null) {
      return (const [], null);
    }
    if (data is! Map) {
      return (const [], 'Unexpected response from server.');
    }
    final root = Map<String, dynamic>.from(data);
    final err = root['status']?.toString();
    if (err == 'error') {
      return (
        const [],
        ApiEnvelope.errorMessage(root) ?? 'Could not load courses.',
      );
    }
    Map<String, dynamic> payload = root;
    if (ApiEnvelope.isSuccess(root)) {
      final d = ApiEnvelope.dataMap(root);
      if (d != null) {
        payload = d;
      } else {
        return (const [], ApiEnvelope.errorMessage(root));
      }
    } else if (root['data'] is Map) {
      payload = Map<String, dynamic>.from(root['data'] as Map);
    }
    final listRaw = payload['courses'] ?? payload['results'];
    if (listRaw is! List) {
      return (const [], null);
    }
    final out = <Map<String, dynamic>>[];
    for (final e in listRaw) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return (out, null);
  }

  Future<void> _searchEducation() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searchError = 'Type something to search (e.g., diabetes, fever, asthma).';
        _results = const [];
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      // MedlinePlus Health Topics (NIH) search web service (XML, no API key).
      final dio = Dio();
      final res = await dio.get<String>(
        'https://wsearch.nlm.nih.gov/ws/query',
        queryParameters: {
          'db': 'healthTopics',
          'term': q,
          'retmax': '20',
        },
        options: Options(responseType: ResponseType.plain),
      );

      final xmlStr = (res.data ?? '').trim();
      if (xmlStr.isEmpty) {
        setState(() {
          _results = const [];
          _searchError = 'No response from education service.';
        });
        return;
      }

      final doc = XmlDocument.parse(xmlStr);
      final items = <_EducationItem>[];
      for (final d in doc.findAllElements('document')) {
        final url = (d.getAttribute('url') ?? '').trim().isNotEmpty
            ? d.getAttribute('url')!.trim()
            : d
                .findElements('content')
                .where((e) => e.getAttribute('name') == 'url')
                .map((e) => e.innerText.trim())
                .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        final titleRaw = d
            .findElements('content')
            .where((e) => e.getAttribute('name') == 'title')
            .map((e) => e.innerText.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        final title = _stripHtml(titleRaw);
        if (url.isEmpty || title.isEmpty) continue;
        items.add(_EducationItem(title: title, url: url));
      }

      setState(() {
        _results = items;
        _searchError = items.isEmpty ? 'No results found.' : null;
      });
    } catch (e) {
      setState(() {
        _results = const [];
        _searchError = 'Search failed. Check internet and try again.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Future<void> _openMedlinePlusSearch(String query) async {
    await _openUrl(_medlinePlusSearchUrl(query));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.primary,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: [
              for (var i = 0; i < _tabTitles.length; i++)
                Tab(
                  icon: Icon(switch (i) {
                    0 => Icons.menu_book_outlined,
                    1 => Icons.school_outlined,
                    _ => Icons.fact_check_outlined,
                  }),
                  text: _tabTitles[i],
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEducation(),
              _buildCourses(),
              _buildMaintenance(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEducation() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Patient education (MedlinePlus)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Search trusted health topics and open the best article for patients.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchEducation(),
          decoration: const InputDecoration(
            labelText: 'Search topic',
            hintText: 'e.g., fever, asthma, diabetes',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _searching ? null : _searchEducation,
            icon: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.article_outlined),
            label: Text(_searching ? 'Searching…' : 'Search MedlinePlus'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              final t = _q.text.trim();
              if (t.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a topic first')),
                );
                return;
              }
              _openMedlinePlusSearch(t);
            },
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('Open in browser'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Popular topics',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final topic in _quickTopics)
              ActionChip(
                label: Text(topic),
                onPressed: _searching
                    ? null
                    : () {
                        _q.text = topic;
                        _searchEducation();
                      },
              ),
          ],
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 12),
          Text(
            _searchError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (_results.isEmpty && _searchError == null)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Column(
              children: const [
                Icon(Icons.search_rounded, size: 56, color: Colors.grey),
                SizedBox(height: 10),
                Text('Search to see education resources'),
              ],
            ),
          )
        else
          ..._results.map(
            (it) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                  child: const Icon(Icons.article_outlined, color: AppColors.primary),
                ),
                title: Text(
                  it.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'MedlinePlus · Tap to read',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _openUrl(it.url),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCourses() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        final f = _api.courses();
        setState(() {
          _coursesFuture = f;
        });
        await f;
      },
      child: FutureBuilder<dynamic>(
        future: _coursesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snap.hasError) {
            final e = snap.error;
            final u = ApiAccessPlaceholder.isUnauthorized(e);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                ApiAccessPlaceholder(
                  title: u ? 'Sign in for courses' : 'Could not load courses',
                  message: ApiAccessPlaceholder.shortMessage(e),
                  requireSignIn: u,
                  onRetry: _reloadCourses,
                ),
              ],
            );
          }
          final parsed = _parseCoursesPayload(snap.data);
          var courses = parsed.$1;
          final apiErr = parsed.$2;
          final filterQ = _courseFilter.text.trim().toLowerCase();
          if (filterQ.isNotEmpty) {
            courses = courses.where((c) {
              final blob = jsonEncode(c).toLowerCase();
              return blob.contains(filterQ);
            }).toList();
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Preventive care courses',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Common topics patients need for prevention and wellness.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _courseFilter,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Filter courses',
                  hintText: 'Search title, tags, summary…',
                  prefixIcon: Icon(Icons.filter_list_rounded),
                ),
              ),
              const SizedBox(height: 14),
              if (apiErr != null && courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    apiErr,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                )
              else if (courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'No courses loaded. Pull to refresh.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                )
              else
                ...courses.map((c) {
                  final title = (c['title'] ?? '').toString();
                  final summary = (c['summary'] ?? '').toString();
                  final minutes = c['minutes']?.toString() ?? '';
                  final level = (c['level'] ?? '').toString();
                  final tagsRaw = c['tags'];
                  final tags = tagsRaw is List
                      ? tagsRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
                      : const <String>[];
                  final resourcesRaw = c['resources'];
                  final resources = resourcesRaw is List
                      ? resourcesRaw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
                      : const <Map<String, dynamic>>[];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              if (minutes.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F).withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$minutes min',
                                    style: const TextStyle(
                                      color: Color(0xFFD32F2F),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (level.isNotEmpty)
                            Text(level, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(summary),
                          ],
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final t in tags.take(6))
                                  Chip(
                                    label: Text(t),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                          if (resources.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Resources', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final r in resources.take(6))
                                  ActionChip(
                                    label: Text((r['title'] ?? 'Open').toString()),
                                    onPressed: () {
                                      final url = (r['url'] ?? '').toString();
                                      if (url.isNotEmpty) _openUrl(url);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMaintenance(BuildContext context) {
    const ages = <(String, String)>[
      ('0–2', 'Infants & toddlers'),
      ('3–6', 'Preschool'),
      ('7–12', 'School age'),
      ('13–18', 'Teens'),
      ('19–39', 'Adults'),
      ('40–64', 'Midlife'),
      ('65+', 'Seniors'),
    ];
    String selected = '19–39';

    return StatefulBuilder(
      builder: (context, setLocal) {
        final plan = _maintenancePlan(selected);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Annual maintenance checklist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Age-wise preventive care, vaccines, and exercise/PT/OT guidance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final a in ages)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(a.$1),
                        selected: selected == a.$1,
                        onSelected: (_) => setLocal(() => selected = a.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              context,
              title: 'Preventive care',
              icon: Icons.health_and_safety_outlined,
              bullets: plan.preventive,
              links: const [
                (
                  'USPSTF recommendations',
                  'https://www.uspreventiveservicestaskforce.org/uspstf/recommendation-topics'
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              title: 'Vaccines',
              icon: Icons.vaccines_outlined,
              bullets: plan.vaccines,
              links: const [
                ('CDC immunization schedule', 'https://www.cdc.gov/vaccines/schedules/'),
              ],
            ),
            const SizedBox(height: 12),
            _exerciseCard(context, title: 'Exercise (home)', items: plan.exercises),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              title: 'PT / OT (when to consider)',
              icon: Icons.accessibility_new_outlined,
              bullets: plan.ptot,
              links: const [
                ('ChoosePT (APTA)', 'https://www.choosept.com/'),
                ('AOTA (OT for consumers)', 'https://www.aota.org/consumers'),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.amber.withValues(alpha: 0.10),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Note: This is general guidance, not medical advice. Always follow your clinician’s recommendations.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> bullets,
    List<(String, String)> links = const [],
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $b'),
              ),
            if (links.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final l in links)
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(l.$2),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l.$1),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(
    BuildContext context, {
    required String title,
    required List<_ExerciseTip> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final it in items)
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                    child: Icon(it.icon, color: AppColors.primary),
                  ),
                  title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(it.body),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _MaintenancePlan _maintenancePlan(String ageKey) {
    switch (ageKey) {
      case '0–2':
        return const _MaintenancePlan(
          preventive: [
            'Well-child visits and growth/development screening.',
            'Sleep safety and nutrition guidance.',
            'Dental: first dentist visit by 1 year (or first tooth).',
          ],
          vaccines: [
            'Follow routine childhood vaccine schedule (DTaP, IPV, Hib, PCV, MMR, Varicella, Hep A/B, Flu).',
          ],
          exercises: [
            _ExerciseTip(Icons.child_care_outlined, 'Tummy time', 'Supervised tummy time daily (as advised).'),
            _ExerciseTip(Icons.directions_walk_outlined, 'Active play', 'Daily movement and play.'),
          ],
          ptot: [
            'PT/OT if delayed milestones, posture concerns, or feeding issues (clinician referral).',
          ],
        );
      case '3–6':
        return const _MaintenancePlan(
          preventive: [
            'Annual checkup; vision/hearing screening.',
            'Dental checkups every 6 months; brushing and fluoride.',
          ],
          vaccines: ['Routine schedule + annual flu; catch-up vaccines as needed.'],
          exercises: [
            _ExerciseTip(Icons.directions_run_outlined, 'Play-based activity', 'At least 60 minutes active play most days.'),
            _ExerciseTip(Icons.sports_soccer_outlined, 'Coordination', 'Jumping, hopping, ball play.'),
          ],
          ptot: ['PT/OT if balance/coordination delays or fine-motor concerns.'],
        );
      case '7–12':
        return const _MaintenancePlan(
          preventive: [
            'Annual wellness visit; nutrition and healthy sleep habits.',
            'Vision/hearing screening; dental every 6 months.',
          ],
          vaccines: ['Annual flu; follow school-age vaccine schedule.'],
          exercises: [
            _ExerciseTip(Icons.sports_basketball_outlined, 'Daily activity', '60 minutes/day moderate to vigorous activity.'),
            _ExerciseTip(Icons.self_improvement_outlined, 'Flexibility', 'Gentle stretching after activity.'),
          ],
          ptot: ['PT if recurrent sports injuries; OT for handwriting/fine-motor issues if needed.'],
        );
      case '13–18':
        return const _MaintenancePlan(
          preventive: [
            'Annual visit; mental health screening; sleep and nutrition.',
            'Sexual health counseling as appropriate.',
          ],
          vaccines: ['HPV series, Tdap, meningococcal; annual flu; catch-up vaccines.'],
          exercises: [
            _ExerciseTip(Icons.fitness_center_outlined, 'Strength', '2–3 days/week strength training (safe form).'),
            _ExerciseTip(Icons.directions_run_outlined, 'Cardio', '150+ min/week moderate activity (or equivalent).'),
          ],
          ptot: ['PT for sports injuries; OT for ergonomics/hand issues.'],
        );
      case '40–64':
        return const _MaintenancePlan(
          preventive: [
            'Annual checkup: blood pressure, diabetes risk, cholesterol (as advised).',
            'Cancer screening per guidelines (colon; breast/cervix/prostate as appropriate).',
          ],
          vaccines: ['Annual flu; COVID boosters as advised; shingles at 50+; Tdap every 10 years.'],
          exercises: [
            _ExerciseTip(Icons.directions_walk_outlined, 'Walking', '30 min brisk walk most days.'),
            _ExerciseTip(Icons.fitness_center_outlined, 'Strength', '2 days/week full-body strength.'),
            _ExerciseTip(Icons.self_improvement_outlined, 'Mobility', 'Daily mobility/stretching 5–10 minutes.'),
          ],
          ptot: ['PT for back/neck/knee pain; OT for work ergonomics or hand arthritis.'],
        );
      case '65+':
        return const _MaintenancePlan(
          preventive: [
            'Annual visit; fall risk and vision/hearing assessment.',
            'Medication review; bone health discussion.',
          ],
          vaccines: ['Annual flu; pneumococcal as advised; shingles; COVID boosters as advised.'],
          exercises: [
            _ExerciseTip(Icons.balance_outlined, 'Balance', 'Balance exercises 3+ days/week (as safe).'),
            _ExerciseTip(Icons.directions_walk_outlined, 'Walking', 'Regular walking as tolerated.'),
            _ExerciseTip(Icons.fitness_center_outlined, 'Strength', '2 days/week strength (safe, supervised if needed).'),
          ],
          ptot: ['PT for balance/gait; OT for home safety and daily activities.'],
        );
      default:
        return const _MaintenancePlan(
          preventive: [
            'Annual checkup: blood pressure, weight, mental health, and lifestyle review.',
            'Screenings based on personal risk factors.',
          ],
          vaccines: ['Annual flu; COVID boosters as advised; Tdap every 10 years.'],
          exercises: [
            _ExerciseTip(Icons.directions_walk_outlined, 'Walking', '150 minutes/week moderate activity.'),
            _ExerciseTip(Icons.fitness_center_outlined, 'Strength', '2 days/week strength training.'),
          ],
          ptot: ['PT/OT if pain, mobility issues, or recovery after injury/surgery.'],
        );
    }
  }
}

class _EducationItem {
  const _EducationItem({required this.title, required this.url});
  final String title;
  final String url;
}

class _MaintenancePlan {
  const _MaintenancePlan({
    required this.preventive,
    required this.vaccines,
    required this.exercises,
    required this.ptot,
  });

  final List<String> preventive;
  final List<String> vaccines;
  final List<_ExerciseTip> exercises;
  final List<String> ptot;
}

class _ExerciseTip {
  const _ExerciseTip(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}
