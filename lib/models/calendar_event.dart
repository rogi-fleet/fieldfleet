import 'package:flutter/material.dart';

enum CalendarEventType {
  task,
  project,
  invoice,
  bill,
  bidPackage,
  rental,
  purchaseOrder,
}

extension CalendarEventTypeX on CalendarEventType {
  String get label {
    switch (this) {
      case CalendarEventType.task:
        return 'Task';
      case CalendarEventType.project:
        return 'Project';
      case CalendarEventType.invoice:
        return 'Invoice';
      case CalendarEventType.bill:
        return 'Bill';
      case CalendarEventType.bidPackage:
        return 'Bid';
      case CalendarEventType.rental:
        return 'Rental';
      case CalendarEventType.purchaseOrder:
        return 'Purchase Order';
    }
  }

  IconData get icon {
    switch (this) {
      case CalendarEventType.task:
        return Icons.check_circle_outline;
      case CalendarEventType.project:
        return Icons.folder_outlined;
      case CalendarEventType.invoice:
        return Icons.receipt_outlined;
      case CalendarEventType.bill:
        return Icons.receipt_long_outlined;
      case CalendarEventType.bidPackage:
        return Icons.gavel_outlined;
      case CalendarEventType.rental:
        return Icons.hardware_outlined;
      case CalendarEventType.purchaseOrder:
        return Icons.local_shipping_outlined;
    }
  }

  Color get color {
    switch (this) {
      case CalendarEventType.task:
        return const Color(0xFF3B82F6);
      case CalendarEventType.project:
        return const Color(0xFF8B5CF6);
      case CalendarEventType.invoice:
        return const Color(0xFF10B981);
      case CalendarEventType.bill:
        return const Color(0xFFF59E0B);
      case CalendarEventType.bidPackage:
        return const Color(0xFF6366F1);
      case CalendarEventType.rental:
        return const Color(0xFF14B8A6);
      case CalendarEventType.purchaseOrder:
        return const Color(0xFFEC4899);
    }
  }
}

class CalendarEvent {
  final String id;
  final String title;
  final String? subtitle;
  final DateTime date;
  final DateTime? endDate;
  final CalendarEventType type;
  final String? route;
  final bool isOverdue;
  final String? status;

  /// Project / job serial number (e.g. "#1042"), if the event belongs to a project.
  final String? jobNumber;

  /// Project / job name, if the event belongs to a project.
  final String? jobName;

  /// Customer or counterparty name (customer for projects/invoices,
  /// vendor for bills/POs).
  final String? customerName;

  /// Customer / project / counterparty address for quick reference.
  final String? customerAddress;

  /// Optional extra key/value details surfaced in the popup dialog
  /// (e.g. Amount, Vendor, Asset, Priority).
  final Map<String, String>? extraDetails;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.subtitle,
    required this.date,
    this.endDate,
    required this.type,
    this.route,
    this.isOverdue = false,
    this.status,
    this.jobNumber,
    this.jobName,
    this.customerName,
    this.customerAddress,
    this.extraDetails,
  });

  bool isOnDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(date.year, date.month, date.day);
    if (endDate == null) return start == d;
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}
