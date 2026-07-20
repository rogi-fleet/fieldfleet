import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/weather_service.dart';
import '../theme/theme.dart';

class WeatherWidget extends StatefulWidget {
  final String? locationQuery;
  final double height;
  final bool compact;

  const WeatherWidget({
    super.key,
    this.locationQuery,
    this.height = 200,
    this.compact = false,
  });

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  Future<WeatherForecast?>? _weatherFuture;
  final WeatherService _weatherService = WeatherService();

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  @override
  void didUpdateWidget(WeatherWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationQuery != widget.locationQuery) {
      _loadWeather();
    }
  }

  void _loadWeather() {
    // Use provided query or fallback to a default (e.g., New York)
    final query = (widget.locationQuery?.isNotEmpty ?? false) 
        ? widget.locationQuery! 
        : 'New York';
        
    setState(() {
      _weatherFuture = _weatherService.getForecast(query);
    });
  }

  bool _useFahrenheit(String country) {
    const usVariants = [
      'United States of America',
      'USA',
      'United States',
      'US',
      'America'
    ];
    return usVariants.contains(country);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: Colors.transparent, // Clean, borderless background
      child: FutureBuilder<WeatherForecast?>(
        future: _weatherFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(
              child: widget.compact 
                ? Icon(Icons.cloud_off, size: 24, color: AppColors.textTertiary)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: 8),
                      Text(
                        'Weather unavailable',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
            );
          }

          final weather = snapshot.data!;
          final current = weather.current;
          final isFahrenheit = _useFahrenheit(weather.location.country);

          if (widget.compact) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (current.condition.icon.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: current.condition.icon,
                      width: 16,
                      height: 16,
                      errorWidget: (context, url, error) =>
                          Icon(Icons.wb_sunny, size: 14, color: AppColors.textTertiary),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    isFahrenheit 
                        ? '${current.tempF.round()}°'
                        : '${current.tempC.round()}°',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          // Full View
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Current Weather Block
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (current.condition.icon.isNotEmpty) ...[
                          CachedNetworkImage(
                            imageUrl: current.condition.icon,
                            width: 48,
                            height: 48,
                            errorWidget: (context, url, error) =>
                                Icon(Icons.wb_sunny, size: 48, color: AppColors.warning),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          isFahrenheit 
                              ? '${current.tempF.round()}°'
                              : '${current.tempC.round()}°',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current.condition.text,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      weather.location.name,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Subtle separator
              Container(
                width: 1,
                height: 60,
                color: AppColors.cardBorder,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              ),

              // Forecast List
              Expanded(
                flex: 3,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: weather.forecastDays.length,
                  itemBuilder: (context, index) {
                    final day = weather.forecastDays[index];
                    final isToday = index == 0;
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isToday ? 'Today' : DateFormat('EEE').format(day.date),
                            style: TextStyle(
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                              color: isToday ? AppColors.info : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (day.condition.icon.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: day.condition.icon,
                              width: 32,
                              height: 32,
                              errorWidget: (context, url, error) =>
                                  Icon(Icons.wb_sunny, size: 28, color: AppColors.warning),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            isFahrenheit
                                ? '${day.maxTempF.round()}°'
                                : '${day.maxTempC.round()}°',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            isFahrenheit
                                ? '${day.minTempF.round()}°'
                                : '${day.minTempC.round()}°',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
