-- RoboSapiens 물류 플랫폼 — MySQL 스키마 (원장 / system of record)
--
-- 이 시스템의 원장은 이 데이터베이스이며, 관제센터·소비자 앱이 들고 있는
-- 메모리 상태는 캐시다. 재기동하면 여기 남은 내용으로 복원된다.
--
-- SQLite(robo_control.db) 스키마 v2와 1:1 대응한다. 타입 매핑:
--   TEXT(ISO8601)  -> DATETIME(6)   (마이크로초까지 보존, 로컬 시각 그대로)
--   INTEGER(0/1)   -> TINYINT(1)
--   TEXT(enum.name)-> VARCHAR(32)   (Dart enum 이름 문자열. ENUM 타입을 쓰지
--                                    않는 이유는 enum 값이 늘 때 DDL 변경을
--                                    강제하지 않기 위함)
--
-- 적용:  mysql -u <user> -p < db/schema.sql

CREATE DATABASE IF NOT EXISTS `robosapiens`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE `robosapiens`;

-- SQLite의 PRAGMA user_version 대응. 마이그레이션 단계를 기록한다.
CREATE TABLE IF NOT EXISTS `schema_version` (
  `id`         TINYINT      NOT NULL DEFAULT 1,
  `version`    INT          NOT NULL,
  `applied_at` DATETIME(6)  NOT NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `chk_schema_version_single_row` CHECK (`id` = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- 마스터 데이터
-- ---------------------------------------------------------------------------

-- 로봇 등록 정보. 텔레메트리와 분리된 마스터 데이터.
-- 등록 해제는 삭제가 아니라 active = 0 + retired_at 기록(이력 보존).
CREATE TABLE IF NOT EXISTS `robots` (
  `id`              VARCHAR(64)  NOT NULL,
  `name`            VARCHAR(128) NOT NULL,
  `model`           VARCHAR(64)  NOT NULL,
  -- TempZone.name 을 콤마로 이어 붙인 값. 예: 'ambient,chilled'
  `zone_rating`     VARCHAR(64)  NOT NULL,
  `home_charger_id` VARCHAR(64)  NOT NULL,
  `reserve`         TINYINT(1)   NOT NULL DEFAULT 0,
  `active`          TINYINT(1)   NOT NULL DEFAULT 1,
  `registered_at`   DATETIME(6)  NOT NULL,
  `retired_at`      DATETIME(6)  NULL,
  PRIMARY KEY (`id`),
  KEY `idx_robots_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 로봇당 최신 스냅샷 1행. 고빈도 위치 갱신은 여기에만 반영한다(UPSERT).
CREATE TABLE IF NOT EXISTS `robot_telemetry` (
  `robot_id`     VARCHAR(64)  NOT NULL,
  `at`           DATETIME(6)  NOT NULL,
  `state`        VARCHAR(32)  NOT NULL,
  `battery`      DOUBLE       NOT NULL,
  `x`            DOUBLE       NOT NULL,
  `y`            DOUBLE       NOT NULL,
  `heading`      DOUBLE       NOT NULL,
  `task_id`      VARCHAR(64)  NULL,
  `progress`     DOUBLE       NOT NULL DEFAULT 0,
  `activity`     VARCHAR(255) NULL,
  `odometer`     DOUBLE       NOT NULL DEFAULT 0,
  `power_saving` TINYINT(1)   NOT NULL DEFAULT 0,
  `completed`    INT          NOT NULL DEFAULT 0,
  `failed`       INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (`robot_id`),
  CONSTRAINT `fk_telemetry_robot` FOREIGN KEY (`robot_id`)
    REFERENCES `robots` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 현장 작업자. 등록 해제도 로봇과 같은 방식(active = 0).
CREATE TABLE IF NOT EXISTS `workers` (
  `id`            VARCHAR(64)  NOT NULL,
  `name`          VARCHAR(128) NOT NULL,
  `role`          VARCHAR(64)  NOT NULL,
  `zone`          VARCHAR(32)  NOT NULL,
  `active`        TINYINT(1)   NOT NULL DEFAULT 1,
  `registered_at` DATETIME(6)  NOT NULL,
  `retired_at`    DATETIME(6)  NULL,
  PRIMARY KEY (`id`),
  KEY `idx_workers_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- 재고
-- ---------------------------------------------------------------------------

-- 로트 = 재고의 최소 관리 단위. FEFO 판단 기준이 expiry.
-- reserved 는 배차 예약분(실물 이동 없음). 가용 = qty - reserved.
CREATE TABLE IF NOT EXISTS `lots` (
  `id`          VARCHAR(64)  NOT NULL,
  `sku`         VARCHAR(64)  NOT NULL,
  `name`        VARCHAR(128) NOT NULL,
  `zone`        VARCHAR(32)  NOT NULL,
  `location_id` VARCHAR(64)  NOT NULL,
  `qty`         INT          NOT NULL,
  `reserved`    INT          NOT NULL DEFAULT 0,
  `expiry`      DATETIME(6)  NOT NULL,
  `received_at` DATETIME(6)  NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_lots_sku_expiry` (`sku`, `expiry`),
  KEY `idx_lots_location` (`location_id`),
  CONSTRAINT `chk_lots_qty`          CHECK (`qty` >= 0),
  CONSTRAINT `chk_lots_reserved`     CHECK (`reserved` >= 0),
  CONSTRAINT `chk_lots_reserved_max` CHECK (`reserved` <= `qty`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 재고 원장 — 수량이 바뀐 모든 사건을 append-only로 남긴다.
-- lot_id 에 FK를 걸지 않는 이유: 로트가 소진·삭제된 뒤에도 이력은 남아야 한다.
CREATE TABLE IF NOT EXISTS `stock_moves` (
  `id`        BIGINT       NOT NULL AUTO_INCREMENT,
  `at`        DATETIME(6)  NOT NULL,
  `lot_id`    VARCHAR(64)  NOT NULL,
  `sku`       VARCHAR(64)  NOT NULL,
  `delta`     INT          NOT NULL,
  `qty_after` INT          NOT NULL,
  -- StockMoveReason.name: inbound|outbound|disposal|adjustment|cycleCount|initial
  `reason`    VARCHAR(32)  NOT NULL,
  `task_id`   VARCHAR(64)  NULL,
  `order_id`  VARCHAR(64)  NULL,
  `operator`  VARCHAR(128) NULL,
  `note`      VARCHAR(512) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_moves_at` (`at`),
  KEY `idx_moves_lot` (`lot_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- 주문 — 소비자 앱과 관제센터의 접점
-- ---------------------------------------------------------------------------

-- expanded = 0 은 관제가 아직 태스크로 전개하지 않은 주문(소비자 앱 접수분).
CREATE TABLE IF NOT EXISTS `orders` (
  `id`           VARCHAR(64)  NOT NULL,
  `customer`     VARCHAR(128) NOT NULL,
  `urgency`      VARCHAR(32)  NOT NULL,
  `created_at`   DATETIME(6)  NOT NULL,
  `due_at`       DATETIME(6)  NOT NULL,
  `line_count`   INT          NOT NULL,
  `state`        VARCHAR(32)  NOT NULL,
  `done_lines`   INT          NOT NULL DEFAULT 0,
  `failed_lines` INT          NOT NULL DEFAULT 0,
  `closed_at`    DATETIME(6)  NULL,
  `source`       VARCHAR(32)  NOT NULL DEFAULT 'auto',
  `expanded`     TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_orders_created` (`created_at`),
  KEY `idx_orders_expanded` (`expanded`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 주문이 담고 있는 품목·수량. lot_id 가 비면 FEFO 규칙으로 관제가 고른다.
CREATE TABLE IF NOT EXISTS `order_lines` (
  `order_id` VARCHAR(64)  NOT NULL,
  `seq`      INT          NOT NULL,
  `sku`      VARCHAR(64)  NOT NULL,
  `name`     VARCHAR(128) NOT NULL,
  `qty`      INT          NOT NULL,
  `lot_id`   VARCHAR(64)  NULL,
  PRIMARY KEY (`order_id`, `seq`),
  KEY `idx_order_lines_order` (`order_id`),
  CONSTRAINT `fk_order_lines_order` FOREIGN KEY (`order_id`)
    REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- 태스크
-- ---------------------------------------------------------------------------

-- order_id 에 FK를 걸지 않는 이유: 완결 태스크는 purgeTerminalBefore 로
-- 주문과 독립적인 주기로 정리된다(SQLite 원본 스키마와 동일).
CREATE TABLE IF NOT EXISTS `tasks` (
  `id`           VARCHAR(64)  NOT NULL,
  `type`         VARCHAR(32)  NOT NULL,
  `title`        VARCHAR(255) NOT NULL,
  `urgency`      VARCHAR(32)  NOT NULL,
  `zone`         VARCHAR(32)  NOT NULL,
  `order_id`     VARCHAR(64)  NULL,
  `sku`          VARCHAR(64)  NULL,
  `lot_id`       VARCHAR(64)  NULL,
  `expiry`       DATETIME(6)  NULL,
  `qty`          INT          NOT NULL DEFAULT 1,
  `requested_by` VARCHAR(64)  NULL,
  `origin_label` VARCHAR(128) NOT NULL,
  `dest_label`   VARCHAR(128) NOT NULL,
  `state`        VARCHAR(32)  NOT NULL,
  `robot_id`     VARCHAR(64)  NULL,
  `step_index`   INT          NOT NULL DEFAULT 0,
  `retries`      INT          NOT NULL DEFAULT 0,
  `fail_reason`  VARCHAR(512) NULL,
  `score`        DOUBLE       NOT NULL DEFAULT 0,
  `created_at`   DATETIME(6)  NOT NULL,
  `assigned_at`  DATETIME(6)  NULL,
  `started_at`   DATETIME(6)  NULL,
  `ended_at`     DATETIME(6)  NULL,
  PRIMARY KEY (`id`),
  KEY `idx_tasks_state` (`state`),
  KEY `idx_tasks_created` (`created_at`),
  KEY `idx_tasks_order` (`order_id`),
  -- purgeTerminalBefore(state IN (...) AND ended_at < ?) 전용
  KEY `idx_tasks_state_ended` (`state`, `ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `task_steps` (
  `task_id`     VARCHAR(64)  NOT NULL,
  `seq`         INT          NOT NULL,
  `kind`        VARCHAR(32)  NOT NULL,
  `label`       VARCHAR(128) NOT NULL,
  `target_x`    DOUBLE       NOT NULL,
  `target_y`    DOUBLE       NOT NULL,
  `duration`    DOUBLE       NOT NULL,
  `resource_id` VARCHAR(64)  NULL,
  PRIMARY KEY (`task_id`, `seq`),
  CONSTRAINT `fk_task_steps_task` FOREIGN KEY (`task_id`)
    REFERENCES `tasks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- RMF Control UI에서 작성한 재사용 가능한 작업 정의. payload에는 지도 Waypoint,
-- 단계와 배정 정보를 JSON으로 보존한다.
CREATE TABLE IF NOT EXISTS `rmf_ui_tasks` (
  `id`         VARCHAR(64)  NOT NULL,
  `name`       VARCHAR(255) NOT NULL,
  `status`     VARCHAR(32)  NOT NULL,
  `payload`    JSON         NOT NULL,
  `created_at` DATETIME(6)  NOT NULL,
  `updated_at` DATETIME(6)  NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_rmf_ui_tasks_status` (`status`),
  KEY `idx_rmf_ui_tasks_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 작업 생성·수정·삭제·상태 변경 이력. 작업 삭제 뒤에도 기록을 보존한다.
CREATE TABLE IF NOT EXISTS `rmf_ui_task_history` (
  `id`          BIGINT      NOT NULL AUTO_INCREMENT,
  `task_id`     VARCHAR(64) NOT NULL,
  `event_type`  VARCHAR(32) NOT NULL,
  `payload`     JSON        NOT NULL,
  `recorded_at` DATETIME(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_rmf_ui_task_history_task` (`task_id`, `recorded_at`),
  KEY `idx_rmf_ui_task_history_at` (`recorded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- 운행 이력 · 안전
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `events` (
  `id`       BIGINT       NOT NULL AUTO_INCREMENT,
  `at`       DATETIME(6)  NOT NULL,
  `severity` VARCHAR(32)  NOT NULL,
  `category` VARCHAR(64)  NOT NULL,
  `source`   VARCHAR(64)  NOT NULL,
  `message`  VARCHAR(512) NOT NULL,
  `task_id`  VARCHAR(64)  NULL,
  `order_id` VARCHAR(64)  NULL,
  PRIMARY KEY (`id`),
  KEY `idx_events_at` (`at`),
  KEY `idx_events_category` (`category`),
  KEY `idx_events_severity` (`severity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `incidents` (
  `id`          VARCHAR(64)  NOT NULL,
  `type`        VARCHAR(32)  NOT NULL,
  `at`          DATETIME(6)  NOT NULL,
  `description` VARCHAR(512) NOT NULL,
  `zone`        VARCHAR(32)  NULL,
  `pos_x`       DOUBLE       NULL,
  `pos_y`       DOUBLE       NULL,
  `radius`      DOUBLE       NOT NULL DEFAULT 0,
  `active`      TINYINT(1)   NOT NULL DEFAULT 1,
  `cleared_at`  DATETIME(6)  NULL,
  -- 조치 이력. 저장소 계층이 구분자로 이어 붙인 문자열.
  `actions`     TEXT         NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_incidents_at` (`at`),
  KEY `idx_incidents_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------------
-- ID 시퀀스 — 재기동해도 번호가 이어지도록 저장한다.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `counters` (
  `name`  VARCHAR(64) NOT NULL,
  `value` BIGINT      NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


INSERT INTO `schema_version` (`id`, `version`, `applied_at`)
VALUES (1, 2, NOW(6))
ON DUPLICATE KEY UPDATE `version` = VALUES(`version`), `applied_at` = NOW(6);
