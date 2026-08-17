-- v12 -> v13
-- WorkCell(로봇팔) Policy 목록을 파일(index.json / policy_bindings.json)에서
-- DB 로 옮긴다. 학습 결과 ZIP 은 그대로 디스크에 두고 기본 정보만 담는다.
--
-- 프로젝트는 이름으로만 적고 FK 를 걸지 않는다. Policy 는 프로젝트보다 오래
-- 남는 자산이라 프로젝트를 지워도 함께 사라지면 안 된다.

START TRANSACTION;

CREATE TABLE IF NOT EXISTS `workcell_policies` (
  `id`                 BIGINT       NOT NULL AUTO_INCREMENT,
  `policy_id`          VARCHAR(191) NOT NULL,
  `name`               VARCHAR(128) NOT NULL,
  `version`            VARCHAR(64)  NOT NULL,
  `project_name`       VARCHAR(255) NULL,
  `object_type`        VARCHAR(128) NOT NULL DEFAULT '',
  `robot_model`        VARCHAR(128) NOT NULL DEFAULT '',
  `archive_name`       VARCHAR(255) NOT NULL DEFAULT 'policy.zip',
  `archive_bytes`      BIGINT       NOT NULL DEFAULT 0,
  `storage_key`        VARCHAR(255) NOT NULL,
  `deployed_workcells` JSON         NOT NULL,
  `source_repository`  VARCHAR(255) NULL,
  `source_revision`    VARCHAR(128) NULL,
  `created_at`         DATETIME(6)  NOT NULL,
  `updated_at`         DATETIME(6)  NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_workcell_policies_policy_id` (`policy_id`),
  KEY `idx_workcell_policies_project` (`project_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `schema_version` (`id`, `version`, `applied_at`)
VALUES (1, 13, NOW(6))
ON DUPLICATE KEY UPDATE `version` = VALUES(`version`), `applied_at` = NOW(6);

COMMIT;
