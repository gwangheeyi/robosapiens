-- v11 -> v12
-- 프로젝트별 시뮬레이션 백엔드, 화면 선택, 좌표 변환 및 백엔드 설정을 보관한다.

START TRANSACTION;

CREATE TABLE IF NOT EXISTS `map_project_simulation_settings` (
  `project_id`           BIGINT      NOT NULL,
  `default_backend`      VARCHAR(16) NOT NULL DEFAULT 'gazebo',
  `simulator_gui`        TINYINT(1)  NOT NULL DEFAULT 0,
  `rviz_enabled`         TINYINT(1)  NOT NULL DEFAULT 0,
  `gazebo_settings`      JSON        NOT NULL,
  `isaac_settings`       JSON        NOT NULL,
  `coordinate_transform` JSON        NOT NULL,
  `updated_at`           DATETIME(6) NOT NULL,
  PRIMARY KEY (`project_id`),
  CONSTRAINT `fk_map_simulation_project` FOREIGN KEY (`project_id`)
    REFERENCES `map_projects` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `map_project_robot_simulation` (
  `project_id` BIGINT       NOT NULL,
  `robot_id`   VARCHAR(64)  NOT NULL,
  `backend`    VARCHAR(16)  NOT NULL,
  `asset_uri`  VARCHAR(512) NOT NULL,
  `prim_path`  VARCHAR(255) NULL,
  `settings`   JSON         NOT NULL,
  `updated_at` DATETIME(6)  NOT NULL,
  PRIMARY KEY (`project_id`, `robot_id`, `backend`),
  CONSTRAINT `fk_map_robot_simulation_robot`
    FOREIGN KEY (`project_id`, `robot_id`)
    REFERENCES `map_project_robots` (`project_id`, `robot_id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `schema_version` (`id`, `version`, `applied_at`)
VALUES (1, 12, NOW(6))
ON DUPLICATE KEY UPDATE `version` = VALUES(`version`), `applied_at` = NOW(6);

COMMIT;
