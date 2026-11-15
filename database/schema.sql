-- ============================================================
-- KLNCE Smart Transport System — Database Schema
-- MySQL 8.0+ | UTF8MB4 for Tamil Unicode support
-- ============================================================

CREATE DATABASE IF NOT EXISTS klnce_transport
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE klnce_transport;

-- ============================================================
-- TABLE: users
-- Stores all system users: students, staff, admins, drivers
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id            INT           PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(100)  NOT NULL,
  email         VARCHAR(100)  UNIQUE NOT NULL,
  phone         VARCHAR(15),
  password_hash VARCHAR(255)  NULL COMMENT 'Legacy bcrypt hash; Firebase Auth is used for sign-in',
  role          ENUM('student','staff','admin','driver') NOT NULL DEFAULT 'student',
  college       ENUM('engineering','arts_science','both') NOT NULL DEFAULT 'engineering',
  fcm_token     VARCHAR(255)  COMMENT 'Firebase Cloud Messaging token for push notifications',
  is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_email (email),
  INDEX idx_role  (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: master_stops
-- Canonical stop registry with Tamil names and aliases
-- ============================================================
CREATE TABLE IF NOT EXISTS master_stops (
  id                 INT           PRIMARY KEY AUTO_INCREMENT,
  standard_name_en   VARCHAR(200)  NOT NULL,
  standard_name_ta   VARCHAR(200)  COMMENT 'Tamil name in Unicode UTF8MB4',
  aliases            TEXT          COMMENT 'JSON array of alternate spellings and abbreviations',
  latitude           DECIMAL(10,8) COMMENT 'GPS latitude (populated later)',
  longitude          DECIMAL(11,8) COMMENT 'GPS longitude (populated later)',
  created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FULLTEXT INDEX ft_names     (standard_name_en),
  INDEX idx_name_en (standard_name_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: schedule_documents
-- Uploaded bus schedule images/PDFs with approval workflow
-- ============================================================
CREATE TABLE IF NOT EXISTS schedule_documents (
  id             INT          PRIMARY KEY AUTO_INCREMENT,
  title          VARCHAR(200) NOT NULL,
  file_url       TEXT         NOT NULL COMMENT 'Firebase Storage or S3 URL',
  file_type      ENUM('image','pdf') NOT NULL,
  trip_direction ENUM('incoming','outgoing') NOT NULL DEFAULT 'incoming',
  college        ENUM('engineering','arts_science','both') NOT NULL DEFAULT 'both',
  effective_date DATE         NOT NULL,
  status         ENUM('draft','verified','published','archived') NOT NULL DEFAULT 'draft',
  created_by     INT          NOT NULL,
  verified_by    INT,
  verified_at    DATETIME,
  published_at   DATETIME,
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by)  REFERENCES users(id),
  FOREIGN KEY (verified_by) REFERENCES users(id),
  INDEX idx_status         (status),
  INDEX idx_effective_date (effective_date),
  INDEX idx_trip_direction (trip_direction)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: bus_routes
-- Individual bus entries within a schedule document
-- ============================================================
CREATE TABLE IF NOT EXISTS bus_routes (
  id                 INT          PRIMARY KEY AUTO_INCREMENT,
  schedule_id        INT          NOT NULL,
  bus_code           VARCHAR(10)  NOT NULL COMMENT 'e.g. K, I1, E, M, IT9',
  route_display_name VARCHAR(200) COMMENT 'Human-readable route name e.g. Thirunagar Route',
  departure_time     VARCHAR(10)  COMMENT 'HH:MM format e.g. 08:00',
  college            ENUM('engineering','arts_science') NOT NULL DEFAULT 'engineering',
  display_order      INT          NOT NULL DEFAULT 0,
  created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (schedule_id) REFERENCES schedule_documents(id) ON DELETE CASCADE,
  INDEX idx_bus_code    (bus_code),
  INDEX idx_schedule_id (schedule_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: route_stops
-- Ordered stops for each bus route with Tamil names and times
-- ============================================================
CREATE TABLE IF NOT EXISTS route_stops (
  id                     INT          PRIMARY KEY AUTO_INCREMENT,
  bus_route_id           INT          NOT NULL,
  stop_order             INT          NOT NULL COMMENT 'Sequence number within the route',
  stop_name_en           VARCHAR(200) NOT NULL,
  stop_name_ta           VARCHAR(200) COMMENT 'Tamil stop name in Unicode UTF8MB4',
  estimated_arrival_time VARCHAR(10)  COMMENT 'HH:MM format; NULL if not specified',
  master_stop_id         INT          COMMENT 'Links to canonical master_stops entry',
  FOREIGN KEY (bus_route_id)   REFERENCES bus_routes(id)    ON DELETE CASCADE,
  FOREIGN KEY (master_stop_id) REFERENCES master_stops(id)  ON DELETE SET NULL,
  INDEX idx_bus_route_id  (bus_route_id),
  INDEX idx_stop_name_en  (stop_name_en),
  INDEX idx_stop_name_ta  (stop_name_ta)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: gps_locations
-- Real-time GPS pings from driver apps
-- ============================================================
CREATE TABLE IF NOT EXISTS gps_locations (
  id            INT           PRIMARY KEY AUTO_INCREMENT,
  bus_code      VARCHAR(10)   NOT NULL,
  driver_id     INT           NOT NULL,
  latitude      DECIMAL(10,8) NOT NULL,
  longitude     DECIMAL(11,8) NOT NULL,
  speed_kmh     DECIMAL(5,2)  COMMENT 'Speed in km/h',
  is_active_trip BOOLEAN      NOT NULL DEFAULT TRUE COMMENT 'FALSE when trip ends',
  recorded_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (driver_id) REFERENCES users(id),
  INDEX idx_bus_code_active (bus_code, is_active_trip),
  INDEX idx_recorded_at     (recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- TABLE: notifications
-- Push notification log for schedule updates, delays, etc.
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id               INT          PRIMARY KEY AUTO_INCREMENT,
  title            VARCHAR(200) NOT NULL,
  body             TEXT         NOT NULL,
  type             ENUM('schedule_update','delay','route_change','holiday','general')
                                NOT NULL DEFAULT 'general',
  sent_by          INT          NOT NULL,
  sent_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  recipient_count  INT          NOT NULL DEFAULT 0 COMMENT 'Number of FCM tokens targeted',
  FOREIGN KEY (sent_by) REFERENCES users(id),
  INDEX idx_sent_at (sent_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- End of schema.sql
-- ============================================================
