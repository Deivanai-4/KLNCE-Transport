USE klnce_transport;

ALTER TABLE users
  MODIFY password_hash VARCHAR(255) NULL
  COMMENT 'Legacy bcrypt hash; Firebase Auth is used for sign-in';

UPDATE users
SET password_hash = NULL;
