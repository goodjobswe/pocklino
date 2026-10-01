import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openPocketDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return databaseFactoryIo.openDatabase(
    path.join(directory.path, 'pocklino-v1.db'),
  );
}
