/// RoboSapiens 물류 플랫폼 공용 계층.
///
/// 관제센터(robo_control)와 소비자 주문 앱(roboapp)이 같은 도메인 모델과
/// 저장소 계약을 공유한다. 저장소 구현을 SQLite에서 PostgreSQL·REST로
/// 바꿔도 이 패키지의 인터페이스는 그대로다.
library;

export 'data/app_database.dart';
export 'data/repositories.dart';
export 'data/sqlite_repositories.dart';
export 'models/enums.dart';
export 'models/event.dart';
export 'models/inventory.dart';
export 'models/robot.dart';
export 'models/task.dart';
export 'models/warehouse.dart';
