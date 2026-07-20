import 'package:flutter/material.dart';

enum CustomerSource {
  referral,
  google,
  facebook,
  instagram,
  website,
  walkIn,
  billboard,
  linkedin,
  yardSign,
  email,
  phone,
  other;

  String get displayName {
    switch (this) {
      case CustomerSource.referral:
        return 'Referral';
      case CustomerSource.google:
        return 'Google Search';
      case CustomerSource.facebook:
        return 'Facebook';
      case CustomerSource.instagram:
        return 'Instagram';
      case CustomerSource.website:
        return 'Website';
      case CustomerSource.walkIn:
        return 'Walk-in';
      case CustomerSource.billboard:
        return 'Billboard';
      case CustomerSource.linkedin:
        return 'LinkedIn';
      case CustomerSource.yardSign:
        return 'Yard Sign';
      case CustomerSource.email:
        return 'Email Campaign';
      case CustomerSource.phone:
        return 'Phone Call';
      case CustomerSource.other:
        return 'Other';
    }
  }

  String get description {
    switch (this) {
      case CustomerSource.referral:
        return 'Referred by existing customer or contact';
      case CustomerSource.google:
        return 'Found via Google search';
      case CustomerSource.facebook:
        return 'Social media - Facebook';
      case CustomerSource.instagram:
        return 'Social media - Instagram';
      case CustomerSource.website:
        return 'Direct website inquiry';
      case CustomerSource.walkIn:
        return 'Walked into office';
      case CustomerSource.billboard:
        return 'Saw billboard advertisement';
      case CustomerSource.linkedin:
        return 'Social media - LinkedIn';
      case CustomerSource.yardSign:
        return 'Saw yard sign';
      case CustomerSource.email:
        return 'Email marketing campaign';
      case CustomerSource.phone:
        return 'Inbound phone call';
      case CustomerSource.other:
        return 'Other source';
    }
  }

  IconData get icon {
    switch (this) {
      case CustomerSource.referral:
        return Icons.people;
      case CustomerSource.google:
        return Icons.search;
      case CustomerSource.facebook:
        return Icons.facebook;
      case CustomerSource.instagram:
        return Icons.camera_alt;
      case CustomerSource.website:
        return Icons.language;
      case CustomerSource.walkIn:
        return Icons.store;
      case CustomerSource.billboard:
        return Icons.signpost;
      case CustomerSource.linkedin:
        return Icons.business;
      case CustomerSource.yardSign:
        return Icons.sign_language;
      case CustomerSource.email:
        return Icons.email;
      case CustomerSource.phone:
        return Icons.phone;
      case CustomerSource.other:
        return Icons.more_horiz;
    }
  }

  bool get requiresReferrerName {
    return this == CustomerSource.referral;
  }

  /// Convert to database value (snake_case)
  String toDbValue() {
    switch (this) {
      case CustomerSource.walkIn:
        return 'walk_in';
      case CustomerSource.yardSign:
        return 'yard_sign';
      default:
        return name;
    }
  }

  static CustomerSource fromString(String source) {
    switch (source.toLowerCase()) {
      case 'referral':
        return CustomerSource.referral;
      case 'google':
        return CustomerSource.google;
      case 'facebook':
        return CustomerSource.facebook;
      case 'instagram':
        return CustomerSource.instagram;
      case 'website':
        return CustomerSource.website;
      case 'walkin':
      case 'walk_in':
        return CustomerSource.walkIn;
      case 'billboard':
        return CustomerSource.billboard;
      case 'linkedin':
        return CustomerSource.linkedin;
      case 'yard_sign':
      case 'yardsign':
      case 'yardSign':
        return CustomerSource.yardSign;
      case 'email':
        return CustomerSource.email;
      case 'phone':
        return CustomerSource.phone;
      case 'other':
        return CustomerSource.other;
      default:
        return CustomerSource.other;
    }
  }
}
