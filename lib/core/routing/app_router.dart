import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/pages/home_page.dart';
import '../../features/scanner/presentation/pages/scanner_page.dart';
import '../../features/scanner/presentation/pages/scan_crop_page.dart';
import '../../features/scanner/presentation/pages/scan_preview_page.dart';
import '../../features/scanner/domain/entities/document_filter_type.dart';
import '../../features/documents/domain/entities/scanned_document.dart';
import '../../features/documents/presentation/pages/document_viewer_page.dart';
import '../../features/home/presentation/pages/documents_page.dart';
import '../../features/tools/presentation/pages/tools_page.dart';
import '../../features/ocr/presentation/pages/ocr_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/presentation/pages/more_settings_page.dart';
import '../../features/tools/presentation/pages/qr_scanner_page.dart';
import '../../features/tools/presentation/pages/id_card_scanner_page.dart';
import '../../features/tools/presentation/pages/pdf_merge_page.dart';
import '../../features/tools/presentation/pages/signature_page.dart';
import '../../features/tools/presentation/pages/watermark_page.dart';
import '../../features/tools/presentation/pages/long_image_page.dart';
import '../../features/tools/presentation/pages/extract_pdf_pages_page.dart';
import '../../features/tools/presentation/pages/id_photo_maker_page.dart';
import '../../features/tools/presentation/pages/protect_pdf_page.dart';
import '../../features/tools/presentation/pages/reorder_pdf_pages_page.dart';
import '../../features/documents/presentation/pages/single_page_viewer_page.dart';
import '../../features/conversion/presentation/pages/document_conversion_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import 'widgets/main_layout.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainLayout(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/documents',
            builder: (context, state) => const DocumentsPage(),
          ),
          GoRoute(
            path: '/tools',
            builder: (context, state) => const ToolsPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/scanner',
        builder: (context, state) {
          final targetId = state.extra is String ? state.extra as String : null;
          return ScannerPage(targetDocumentId: targetId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/scan_crop',
        builder: (context, state) {
          final args = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : <String, dynamic>{};
          return ScanCropPage(
            originalImageBytes: args['imageBytes'],
            initialCorners: args['corners'],
            rotation: args['rotation'] ?? 0,
            filterIndex: args['filter'] ?? DocumentFilterType.auto.index,
            targetDocumentId: args['targetDocumentId'],
            targetPageIndex: args['targetPageIndex'],
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/scan_preview',
        builder: (context, state) {
          final data = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : <String, dynamic>{};
          return ScanPreviewPage(
            originalImageBytes: data['imageBytes'],
            rawCapturedBytes: data['rawCapturedBytes'],
            initialCorners: data['corners'],
            rotation: data['rotation'],
            initialFilterIndex: data['filter'] ?? DocumentFilterType.auto.index,
            targetDocumentId: data['targetDocumentId'],
            targetPageIndex: data['targetPageIndex'],
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/document_viewer',
        builder: (context, state) {
          if (state.extra is ScannedDocument) {
            return DocumentViewerPage(document: state.extra as ScannedDocument);
          }
          return const Scaffold(body: Center(child: Text('Document not found')));
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/single_page_viewer',
        builder: (context, state) {
          final data = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : <String, dynamic>{};
          final doc = data['document'] as ScannedDocument?;
          if (doc != null) {
            return SinglePageViewerPage(
              document: doc,
              initialPageIndex: (data['initialPageIndex'] as int?) ?? 0,
            );
          }
          return const Scaffold(body: Center(child: Text('Page not found')));
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ocr',
        builder: (context, state) => OcrPage(
          initialFormat: state.uri.queryParameters['mode'] ?? 'text',
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/qr_scanner',
        builder: (context, state) => const QrScannerPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/id_card_scanner',
        builder: (context, state) => const IDCardScannerPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/pdf_merge',
        builder: (context, state) => const PdfMergePage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/signature',
        builder: (context, state) => const SignaturePage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/watermark',
        builder: (context, state) => const WatermarkPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/pdf_to_long_image',
        builder: (context, state) => const LongImagePage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/extract_pdf_pages',
        builder: (context, state) => const ExtractPdfPagesPage(exportAsImagesOnly: false),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/pdf_to_images',
        builder: (context, state) => const ExtractPdfPagesPage(exportAsImagesOnly: true),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/protect_pdf',
        builder: (context, state) => const ProtectPdfPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/reorder_pdf_pages',
        builder: (context, state) => const ReorderPdfPagesPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/id_photo_maker',
        builder: (context, state) => const IDPhotoMakerPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/more_settings',
        builder: (context, state) => const MoreSettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/convert_document',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return DocumentConversionPage(
            document: data['document'] as ScannedDocument,
            format: data['format'] as ExportFormatType,
          );
        },
      ),
    ],
  );
}
