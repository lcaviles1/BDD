SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- BIND (paramétrico): SQL*Plus NO acepta DATE aquí, así que se guarda como TEXTO
--------------------------------------------------------------------------------
VAR b_fecha_proceso VARCHAR2(19);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS');

--------------------------------------------------------------------------------
-- BLOQUE PL/SQL ANÓNIMO: Generación de credenciales (USUARIO / CLAVE)
--------------------------------------------------------------------------------
DECLARE
  --------------------------------------------------------------------------
  -- Fecha de proceso paramétrica (convertida desde el bind texto)
  --------------------------------------------------------------------------
  v_fecha_proceso DATE :=
    TO_DATE(
      NVL(:b_fecha_proceso, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')),
      'YYYY-MM-DD HH24:MI:SS'
    );

  --------------------------------------------------------------------------
  -- Parámetros del rango solicitado (id_emp 100..320, paso 10)
  --------------------------------------------------------------------------
  c_id_ini CONSTANT NUMBER := 100;
  c_id_fin CONSTANT NUMBER := 320;
  c_paso   CONSTANT NUMBER := 10;

  --------------------------------------------------------------------------
  -- Control de transacción: contador vs total
  --------------------------------------------------------------------------
  v_total_empleados NUMBER := 0;
  v_iter_ok         NUMBER := 0;

  --------------------------------------------------------------------------
  -- Variables %TYPE (>= 3) para cumplir requerimiento
  --------------------------------------------------------------------------
  v_id_emp         empleado.id_emp%TYPE;
  v_numrun_emp     empleado.numrun_emp%TYPE;
  v_dvrun_emp      empleado.dvrun_emp%TYPE;
  v_appaterno_emp  empleado.appaterno_emp%TYPE;
  v_apmaterno_emp  empleado.apmaterno_emp%TYPE;
  v_pnombre_emp    empleado.pnombre_emp%TYPE;
  v_snombre_emp    empleado.snombre_emp%TYPE;
  v_fecha_nac      empleado.fecha_nac%TYPE;
  v_fecha_contrato empleado.fecha_contrato%TYPE;
  v_sueldo_base    empleado.sueldo_base%TYPE;
  v_estado_civil   estado_civil.nombre_estado_civil%TYPE;

  -- Salida (tabla destino)
  v_nombre_empleado usuario_clave.nombre_empleado%TYPE;
  v_nombre_usuario  usuario_clave.nombre_usuario%TYPE;
  v_clave_usuario   usuario_clave.clave_usuario%TYPE;

  --------------------------------------------------------------------------
  -- Auxiliares de cálculo (PL/SQL)
  --------------------------------------------------------------------------
  v_annos_trab      NUMBER;

  v_run_str         VARCHAR2(20);
  v_3er_dig_run     VARCHAR2(1);
  v_anio_nac_mas2   NUMBER;

  v_ult3_sueldo_str VARCHAR2(3);

  v_ap_paterno_low  VARCHAR2(30);
  v_len_ap          PLS_INTEGER;
  v_letras_ap       VARCHAR2(2);

  v_mmYYYY          VARCHAR2(6);

BEGIN
  ----------------------------------------------------------------------------
  -- SQL #1: TRUNCATE (re-ejecutable)
  ----------------------------------------------------------------------------
  EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';

  ----------------------------------------------------------------------------
  -- SQL #2: Total real a procesar (MISMO filtro que el loop: rango + paso 10)
  ----------------------------------------------------------------------------
  SELECT COUNT(*)
    INTO v_total_empleados
    FROM empleado
   WHERE id_emp BETWEEN c_id_ini AND c_id_fin
     AND MOD(id_emp, c_paso) = 0;

  ----------------------------------------------------------------------------
  -- PL/SQL: procesar empleados del rango (paso 10)
  ----------------------------------------------------------------------------
  FOR r IN (
    SELECT id_emp
      FROM empleado
     WHERE id_emp BETWEEN c_id_ini AND c_id_fin
       AND MOD(id_emp, c_paso) = 0
     ORDER BY id_emp
  ) LOOP
    BEGIN
      ------------------------------------------------------------------------
      -- SQL #3: obtener datos base (sin cálculos de negocio)
      ------------------------------------------------------------------------
      SELECT e.id_emp, e.numrun_emp, e.dvrun_emp,
             e.appaterno_emp, e.apmaterno_emp,
             e.pnombre_emp, e.snombre_emp,
             e.fecha_nac, e.fecha_contrato, e.sueldo_base,
             ec.nombre_estado_civil
        INTO v_id_emp, v_numrun_emp, v_dvrun_emp,
             v_appaterno_emp, v_apmaterno_emp,
             v_pnombre_emp, v_snombre_emp,
             v_fecha_nac, v_fecha_contrato, v_sueldo_base,
             v_estado_civil
        FROM empleado e
        JOIN estado_civil ec
          ON ec.id_estado_civil = e.id_estado_civil
       WHERE e.id_emp = r.id_emp;

      ------------------------------------------------------------------------
      -- CÁLCULOS (TODO EN PL/SQL)
      ------------------------------------------------------------------------

      -- Años trabajados
      v_annos_trab := TRUNC(MONTHS_BETWEEN(v_fecha_proceso, v_fecha_contrato) / 12);

      -- NOMBRE_EMPLEADO (FORMATO FIGURA):
      -- PNOMBRE + SNOMBRE + APPATERNO + APMATERNO
      v_nombre_empleado :=
        REGEXP_REPLACE(
          RTRIM(
            v_pnombre_emp || ' ' ||
            NVL(v_snombre_emp, '') || ' ' ||
            v_appaterno_emp || ' ' ||
            v_apmaterno_emp
          ),
          '\s+',
          ' '
        );

      -- NOMBRE_USUARIO (FORMATO FIGURA):
      -- 1) 1ra letra estado civil (minúscula)
      -- 2) 3 primeras letras primer nombre (MAYÚSCULA)
      -- 3) largo del primer nombre
      -- 4) *
      -- 5) último dígito sueldo base
      -- 6) DV RUN
      -- 7) años trabajados
      -- 8) si <10 => X
      v_nombre_usuario :=
          LOWER(SUBSTR(v_estado_civil, 1, 1)) ||
          UPPER(SUBSTR(v_pnombre_emp,  1, 3)) ||
          TO_CHAR(LENGTH(v_pnombre_emp)) ||
          '*' ||
          TO_CHAR(MOD(ROUND(v_sueldo_base), 10)) ||
          v_dvrun_emp ||
          TO_CHAR(v_annos_trab) ||
          CASE WHEN v_annos_trab < 10 THEN 'X' ELSE '' END;

      -- CLAVE
      v_run_str     := TO_CHAR(v_numrun_emp);
      v_3er_dig_run := SUBSTR(v_run_str, 3, 1);

      v_anio_nac_mas2 := EXTRACT(YEAR FROM v_fecha_nac) + 2;

      v_ult3_sueldo_str := LPAD(TO_CHAR(MOD(ROUND(v_sueldo_base) - 1, 1000)), 3, '0');

      v_ap_paterno_low := LOWER(v_appaterno_emp);
      v_len_ap := LENGTH(v_ap_paterno_low);

      IF v_estado_civil IN ('CASADO', 'ACUERDO DE UNION CIVIL') THEN
        v_letras_ap := SUBSTR(v_ap_paterno_low, 1, 2);
      ELSIF v_estado_civil IN ('DIVORCIADO', 'SOLTERO') THEN
        v_letras_ap := SUBSTR(v_ap_paterno_low, 1, 1) || SUBSTR(v_ap_paterno_low, v_len_ap, 1);
      ELSIF v_estado_civil = 'VIUDO' THEN
        v_letras_ap := SUBSTR(v_ap_paterno_low, v_len_ap-2, 1) || SUBSTR(v_ap_paterno_low, v_len_ap-1, 1);
      ELSIF v_estado_civil = 'SEPARADO' THEN
        v_letras_ap := SUBSTR(v_ap_paterno_low, v_len_ap-1, 2);
      ELSE
        v_letras_ap := SUBSTR(v_ap_paterno_low, 1, 2);
      END IF;

      v_mmYYYY := TO_CHAR(v_fecha_proceso, 'MMYYYY');

      v_clave_usuario :=
          v_3er_dig_run ||
          TO_CHAR(v_anio_nac_mas2) ||
          v_ult3_sueldo_str ||
          v_letras_ap ||
          TO_CHAR(v_id_emp) ||
          v_mmYYYY;

      ------------------------------------------------------------------------
      -- SQL #4: insert final
      ------------------------------------------------------------------------
      INSERT INTO usuario_clave
        (id_emp, numrun_emp, dvrun_emp, nombre_empleado, nombre_usuario, clave_usuario)
      VALUES
        (v_id_emp, v_numrun_emp, v_dvrun_emp, v_nombre_empleado, v_nombre_usuario, v_clave_usuario);

      v_iter_ok := v_iter_ok + 1;

    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error en id_emp=' || r.id_emp || ' -> ' || SQLERRM);
    END;
  END LOOP;

  ----------------------------------------------------------------------------
  -- COMMIT solo si se procesó TODO
  ----------------------------------------------------------------------------
  IF v_iter_ok = v_total_empleados THEN
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK: ' || v_iter_ok || '/' || v_total_empleados || ' procesados. COMMIT hecho.');
  ELSE
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || v_iter_ok || '/' || v_total_empleados || ' procesados. ROLLBACK hecho.');
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('FALLÓ (global): ' || SQLERRM);
END;
/
--------------------------------------------------------------------------------
-- PRUEBAS (para evidencias: screenshots)
--------------------------------------------------------------------------------

-- Prueba 1: Conteo generado
SELECT COUNT(*) AS total_generado
  FROM usuario_clave;

-- Prueba 2: Ver datos
SELECT id_emp, numrun_emp, dvrun_emp, nombre_empleado, nombre_usuario, clave_usuario
  FROM usuario_clave
 ORDER BY id_emp;

-- Prueba 3: Validación largos
SELECT MAX(LENGTH(nombre_usuario)) AS max_len_usuario,
       MAX(LENGTH(clave_usuario))  AS max_len_clave
  FROM usuario_clave;



