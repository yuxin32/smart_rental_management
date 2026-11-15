class AdminTenantPreview {
  const AdminTenantPreview({
    required this.id,
    required this.name,
    required this.email,
    required this.unit,
    required this.status,
    required this.verification,
    required this.lease,
  });

  final String id;
  final String name;
  final String email;
  final String unit;
  final String status;
  final String verification;
  final String lease;
}

class AdminMaintenancePreview {
  const AdminMaintenancePreview({
    required this.id,
    required this.title,
    required this.tenant,
    required this.unit,
    required this.status,
    required this.priority,
    required this.date,
    required this.description,
  });

  final String id;
  final String title;
  final String tenant;
  final String unit;
  final String status;
  final String priority;
  final String date;
  final String description;
}

abstract final class AdminPreviewData {
  static const administratorName = 'Nur Aina';
  static const propertyName = 'Seri Mutiara Apartments';

  static const tenants = <AdminTenantPreview>[
    AdminTenantPreview(
      id: 'TNT-001',
      name: 'Alex Tan',
      email: 'alex.tan@example.com',
      unit: 'Block A · A-12-08',
      status: 'Active',
      verification: 'Verified',
      lease: '1 Jan 2026 – 31 Dec 2026',
    ),
    AdminTenantPreview(
      id: 'TNT-002',
      name: 'Nur Izzati',
      email: 'nur.izzati@example.com',
      unit: 'Block B · B-05-03',
      status: 'Active',
      verification: 'Verified',
      lease: '15 Feb 2026 – 14 Feb 2027',
    ),
    AdminTenantPreview(
      id: 'TNT-003',
      name: 'Daniel Lim',
      email: 'daniel.lim@example.com',
      unit: 'Not assigned',
      status: 'Pending',
      verification: 'Review required',
      lease: 'Pending verification',
    ),
    AdminTenantPreview(
      id: 'TNT-004',
      name: 'Siti Hajar',
      email: 'siti.hajar@example.com',
      unit: 'Block B · B-08-07',
      status: 'Active',
      verification: 'Verified',
      lease: '1 Mar 2026 – 28 Feb 2027',
    ),
  ];

  static const maintenanceRequests = <AdminMaintenancePreview>[
    AdminMaintenancePreview(
      id: 'MR-1048',
      title: 'Kitchen ceiling light is not working',
      tenant: 'Alex Tan',
      unit: 'A-12-08',
      status: 'New',
      priority: 'Medium',
      date: 'Today, 9:42 AM',
      description:
          'The main ceiling light in the kitchen stopped working after a power interruption.',
    ),
    AdminMaintenancePreview(
      id: 'MR-1047',
      title: 'Water leaking under bathroom sink',
      tenant: 'Nur Izzati',
      unit: 'B-05-03',
      status: 'In progress',
      priority: 'High',
      date: 'Yesterday, 4:18 PM',
      description:
          'There is a small but continuous leak underneath the bathroom sink.',
    ),
    AdminMaintenancePreview(
      id: 'MR-1042',
      title: 'Bedroom door handle is loose',
      tenant: 'Siti Hajar',
      unit: 'B-08-07',
      status: 'Resolved',
      priority: 'Low',
      date: '18 Mar 2026',
      description: 'The bedroom door handle was loose and required tightening.',
    ),
  ];
}
