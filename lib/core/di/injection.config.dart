// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../../features/documents/data/repositories/local_document_repository.dart'
    as _i365;
import '../../features/documents/data/services/export_service.dart' as _i244;
import '../../features/documents/data/services/pdf_export_service.dart'
    as _i816;
import '../../features/documents/presentation/providers/document_provider.dart'
    as _i500;
import '../../features/scanner/data/services/opencv_document_processor_service.dart'
    as _i454;
import '../../features/scanner/domain/interfaces/i_document_processor.dart'
    as _i934;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.lazySingleton<_i365.LocalDocumentRepository>(
      () => _i365.LocalDocumentRepository(),
    );
    gh.lazySingleton<_i244.ExportService>(() => _i244.ExportService());
    gh.lazySingleton<_i816.PdfExportService>(() => _i816.PdfExportService());
    gh.lazySingleton<_i934.IDocumentProcessor>(
      () => _i454.OpencvDocumentProcessorService(),
    );
    gh.lazySingleton<_i500.DocumentProvider>(
      () => _i500.DocumentProvider(
        gh<_i365.LocalDocumentRepository>(),
        gh<_i244.ExportService>(),
      ),
    );
    return this;
  }
}
