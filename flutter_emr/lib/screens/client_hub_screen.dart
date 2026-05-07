import 'package:flutter/material.dart';

class ClientHubScreen extends StatelessWidget {
  const ClientHubScreen({super.key, this.onNavigateToShellTab});

  /// Switch main [AppShell] tab (e.g. open Medical records).
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFD32F2F),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(icon: Icon(Icons.home), text: 'Home'),
                Tab(icon: Icon(Icons.person), text: 'Profile'),
                Tab(icon: Icon(Icons.card_membership), text: 'Plan'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildHomeTab(context),
                _buildProfileTab(context),
                _buildPlanTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          context,
          icon: Icons.folder_shared_outlined,
          title: 'Medical records & AI',
          subtitle: 'Charts, visits, and AI-assisted summaries',
          color: const Color(0xFF673AB7),
          onTap: () => onNavigateToShellTab?.call(17),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.medical_services,
          title: 'Health Overview',
          subtitle: 'Your medical summary at a glance',
          color: const Color(0xFF4CAF50),
          onTap: () => onNavigateToShellTab?.call(0),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.history,
          title: 'Appointment History',
          subtitle: 'View past and upcoming visits',
          color: const Color(0xFF2196F3),
          onTap: () => onNavigateToShellTab?.call(6),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.receipt_long,
          title: 'Billing & Invoices',
          subtitle: 'Manage your payments',
          color: const Color(0xFF9C27B0),
        ),
        const SizedBox(height: 24),
        Text(
          'Recent Activity',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F5E9),
              child: Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
            ),
            title: const Text('Appointment Completed'),
            subtitle: const Text('Dr. Smith - General Checkup'),
            trailing: const Text(
              '2 days ago',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.payment, color: Color(0xFF2196F3)),
            ),
            title: const Text('Payment Successful'),
            subtitle: const Text('Invoice #1234 - \$50.00'),
            trailing: const Text(
              '5 days ago',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              const CircleAvatar(
                radius: 50,
                backgroundColor: Color(0xFFD32F2F),
                child: Icon(Icons.person, size: 50, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'John Doe',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'john.doe@email.com',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoTile(Icons.badge, 'Full Name', 'John Doe'),
        _buildInfoTile(Icons.email, 'Email', 'john.doe@email.com'),
        _buildInfoTile(Icons.phone, 'Phone', '+1 234 567 8900'),
        _buildInfoTile(Icons.location_on, 'Address', '123 Main Street, City'),
        _buildInfoTile(Icons.calendar_today, 'Date of Birth', 'Jan 15, 1990'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.edit),
          label: const Text('Edit Profile'),
        ),
      ],
    );
  }

  Widget _buildPlanTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 4,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Plan',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\$49/month',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Up to 15 Appointments/month',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'AI Assistant Access',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Active until Dec 31, 2026',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Available Plans',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Basic', '\$5/month', 'Free', [
          '1 Visit/month',
          'Basic Support',
        ]),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Pro', '\$30/month', 'Popular', [
          '3 Visits/month',
          'Priority Support',
        ]),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Enterprise', '\$75/month', 'Best Value', [
          '7 Visits/month',
          '24/7 Support',
          'AI Features',
        ]),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD32F2F)),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    String name,
    String price,
    String badge,
    List<String> features,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: badge == 'Popular' || badge == 'Best Value'
                      ? const BoxDecoration(
                          color: Color(0xFFD32F2F),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        )
                      : null,
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      color: badge != 'Free' ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              price,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 8),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    Text(f, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
