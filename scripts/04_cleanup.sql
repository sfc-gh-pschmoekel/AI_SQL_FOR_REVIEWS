/*============================================================
  04_cleanup.sql — Remove demo environment
  
  Run this to clean up all demo objects after the session.
============================================================*/

USE ROLE SYSADMIN;

DROP DATABASE IF EXISTS CORTEX_AI_DEMO;
DROP WAREHOUSE IF EXISTS CORTEX_AI_DEMO_WH;

SELECT 'Cleanup complete. All demo objects removed.' AS STATUS;
