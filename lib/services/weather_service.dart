import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WeatherService {
  static const String _apiKey = String.fromEnvironment('WEATHER_API_KEY');
  static const String _baseUrl = 'https://api.weatherapi.com/v1';

  Future<WeatherForecast?> getForecast(String query, {int days = 3}) async {
    if (_apiKey.isEmpty) {
      if (kDebugMode) debugPrint('WeatherAPI key not configured (WEATHER_API_KEY).');
      return null;
    }

    try {
      final url = Uri.parse('$_baseUrl/forecast.json?key=$_apiKey&q=$query&days=$days&aqi=no&alerts=no');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return WeatherForecast.fromJson(data);
      } else {
        debugPrint('Failed to load weather data: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching weather data: $e');
      return null;
    }
  }
}

class WeatherForecast {
  final CurrentWeather current;
  final List<DayForecast> forecastDays;
  final Location location;

  WeatherForecast({
    required this.current,
    required this.forecastDays,
    required this.location,
  });

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    return WeatherForecast(
      current: CurrentWeather.fromJson(json['current']),
      forecastDays: (json['forecast']['forecastday'] as List)
          .map((day) => DayForecast.fromJson(day))
          .toList(),
      location: Location.fromJson(json['location']),
    );
  }
}

class Location {
  final String name;
  final String region;
  final String country;

  Location({
    required this.name,
    required this.region,
    required this.country,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      name: json['name'] ?? '',
      region: json['region'] ?? '',
      country: json['country'] ?? '',
    );
  }
}

class CurrentWeather {
  final double tempC;
  final double tempF;
  final Condition condition;
  final double windKph;
  final int humidity;

  CurrentWeather({
    required this.tempC,
    required this.tempF,
    required this.condition,
    required this.windKph,
    required this.humidity,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      tempC: (json['temp_c'] as num).toDouble(),
      tempF: (json['temp_f'] as num).toDouble(),
      condition: Condition.fromJson(json['condition']),
      windKph: (json['wind_kph'] as num).toDouble(),
      humidity: json['humidity'] as int,
    );
  }
}

class DayForecast {
  final DateTime date;
  final double maxTempC;
  final double maxTempF;
  final double minTempC;
  final double minTempF;
  final Condition condition;
  final int dailyChanceOfRain;

  DayForecast({
    required this.date,
    required this.maxTempC,
    required this.maxTempF,
    required this.minTempC,
    required this.minTempF,
    required this.condition,
    required this.dailyChanceOfRain,
  });

  factory DayForecast.fromJson(Map<String, dynamic> json) {
    final day = json['day'];
    return DayForecast(
      date: DateTime.parse(json['date']),
      maxTempC: (day['maxtemp_c'] as num).toDouble(),
      maxTempF: (day['maxtemp_f'] as num).toDouble(),
      minTempC: (day['mintemp_c'] as num).toDouble(),
      minTempF: (day['mintemp_f'] as num).toDouble(),
      condition: Condition.fromJson(day['condition']),
      dailyChanceOfRain: day['daily_chance_of_rain'] as int,
    );
  }
}

class Condition {
  final String text;
  final String icon;
  final int code;

  Condition({
    required this.text,
    required this.icon,
    required this.code,
  });

  factory Condition.fromJson(Map<String, dynamic> json) {
    return Condition(
      text: json['text'] ?? '',
      icon: json['icon'] != null ? 'https:${json['icon']}' : '',
      code: json['code'] as int,
    );
  }
}
