import 'package:smart_rental_management/owner_provider/services/backend/notification_snapshot.dart';

const notificationActor = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const notificationId = '11111111-1111-4111-8111-111111111111';
const notificationBooking = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> notificationJson(
        {NotificationFilter filter = NotificationFilter.all,
        bool read = false,
        String id = notificationId,
        String status = 'Pending',
        bool more = false}) =>
    {
      'recipient_id': notificationActor,
      'filter': filter.name,
      'as_of': '2026-10-23T14:00:00+00:00',
      'total_count': 1,
      'unread_count': read ? 0 : 1,
      'action_count': status == 'Pending' ? 1 : 0,
      'items': [
        {
          'id': id,
          'booking_id': notificationBooking,
          'event_status': status,
          'happened_at': '2026-10-23T13:00:00+00:00',
          'unit_name': 'Real unit',
          'building_name': 'Real building',
          'service_name': 'Standard cleaning',
          'is_read': read,
          'actionable': status == 'Pending'
        }
      ],
      'next_cursor':
          more ? {'timestamp': '2026-10-23T13:00:00+00:00', 'id': id} : null
    };
NotificationSnapshot notificationReport(
        {NotificationFilter filter = NotificationFilter.all,
        bool read = false,
        String id = notificationId,
        bool more = false}) =>
    NotificationSnapshot.parse(
        notificationJson(filter: filter, read: read, id: id, more: more),
        notificationActor,
        filter);
