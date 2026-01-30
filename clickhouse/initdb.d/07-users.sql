CREATE USER 'reader' IDENTIFIED WITH plaintext_password  BY 'password';

GRANT SELECT ON flows.* TO reader;
