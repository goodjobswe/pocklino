import 'package:sembast_web/sembast_web.dart';

Future<Database> openPocketDatabase() =>
    databaseFactoryWeb.openDatabase('pocklino-v1');
