/// Reference to a PDF page rendered behind the floorplan canvas as a faded
/// underlay. Used when a user wants to trace or annotate an uploaded plan.
///
/// [transform] is a 6-element row-major affine matrix (a,b,c,d,e,f) mapping
/// the PDF page to scene coordinates so the user can scale/rotate the
/// underlay to match the wall they're tracing.
class BackgroundPdf {
  final String fileUrl;
  final String? storagePath;
  final int pageIndex;
  final double opacity;
  final List<double> transform;

  const BackgroundPdf({
    required this.fileUrl,
    this.storagePath,
    this.pageIndex = 0,
    this.opacity = 0.35,
    this.transform = const [1, 0, 0, 1, 0, 0],
  });

  BackgroundPdf copyWith({
    String? fileUrl,
    String? storagePath,
    int? pageIndex,
    double? opacity,
    List<double>? transform,
  }) =>
      BackgroundPdf(
        fileUrl: fileUrl ?? this.fileUrl,
        storagePath: storagePath ?? this.storagePath,
        pageIndex: pageIndex ?? this.pageIndex,
        opacity: opacity ?? this.opacity,
        transform: transform ?? this.transform,
      );

  Map<String, dynamic> toJson() => {
        'fileUrl': fileUrl,
        if (storagePath != null) 'storagePath': storagePath,
        'pageIndex': pageIndex,
        'opacity': opacity,
        'transform': transform,
      };

  factory BackgroundPdf.fromJson(Map<String, dynamic> json) => BackgroundPdf(
        fileUrl: json['fileUrl'] as String,
        storagePath: json['storagePath'] as String?,
        pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.35,
        transform: ((json['transform'] as List?) ?? const [1, 0, 0, 1, 0, 0])
            .cast<num>()
            .map((n) => n.toDouble())
            .toList(),
      );
}
