import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

import '../services/catalog_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';

/// Patient Education (online medical resources) + legacy `GET /api/v1/courses/`.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  late final CatalogApi _api = CatalogApi(widget.apiClient);
  late Future<dynamic> _coursesFuture = _api.courses();

  final _q = TextEditingController();
  bool _searching = false;
  String? _searchError;
  List<_EducationItem> _results = const [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _reloadCourses() {
    setState(() => _coursesFuture = _api.courses());
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
        final url = d
            .findElements('content')
            .where((e) => e.getAttribute('name') == 'url')
            .map((e) => e.innerText.trim())
            .where((s) => s.isNotEmpty)
            .cast<String?>()
            .firstWhere((e) => e != null, orElse: () => null);
        final title = d
            .findElements('content')
            .where((e) => e.getAttribute('name') == 'title')
            .map((e) => e.innerText.trim())
            .where((s) => s.isNotEmpty)
            .cast<String?>()
            .firstWhere((e) => e != null, orElse: () => null);
        if (url == null || title == null) continue;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFD32F2F),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(icon: Icon(Icons.menu_book_outlined), text: 'Education'),
                Tab(icon: Icon(Icons.school_outlined), text: 'Courses'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildEducation(),
                _buildCourses(),
              ],
            ),
          ),
        ],
      ),
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchEducation(),
                decoration: const InputDecoration(
                  labelText: 'Search topic',
                  hintText: 'e.g., fever, asthma, diabetes',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _searching ? null : _searchEducation,
              child: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Search'),
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
                leading: const Icon(Icons.article_outlined),
                title: Text(it.title),
                subtitle: Text(it.url, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        setState(() => _coursesFuture = f);
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
          final data = snap.data;
          final root = data is Map ? data : const {};
          final payload = (root['data'] is Map ? root['data'] as Map : root);
          final listRaw = payload['courses'] ?? payload['results'] ?? const [];
          final courses = listRaw is List ? listRaw.whereType<Map>().toList() : const <Map>[];

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
              if (courses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('No courses available yet.')),
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
}

class _EducationItem {
  const _EducationItem({required this.title, required this.url});
  final String title;
  final String url;
}
