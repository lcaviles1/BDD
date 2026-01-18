
/* =====================================================================
   PRY2206 - Actividad Sumativa S2
   Entrega final: Script maestro con TRUNCATE + variables BIND + cargas
   Autor: Lucas Avilés (usuario SUMATIVA_2206_P1)
   ===================================================================== */
   
  

/* ---------- Parámetros (BIND) ---------- */
VARIABLE p_anno               NUMBER
VARIABLE p_movil_pct          NUMBER
VARIABLE p_movil_extra_pct    NUMBER
VARIABLE p_colacion_mensual   NUMBER
VARIABLE p_bono_especial_pct  NUMBER
VARIABLE p_cargo_default      VARCHAR2(30)

BEGIN
  :p_anno              := EXTRACT(YEAR FROM SYSDATE);  -- Año de proceso
  :p_movil_pct         := 6;                           -- % movilización normal mensual
  :p_movil_extra_pct   := 0;                           -- % adicional (si aplica)
  :p_colacion_mensual  := 80000;                       -- Colación mensual fija
  :p_bono_especial_pct := 3;                           -- Bono especial anual (% de sueldo base anual)
  :p_cargo_default     := 'Empleado';                  -- Cargo por defecto en INFO_SII
END;
/
/* Verificación rápida de parámetros
SELECT :p_anno, :p_movil_pct, :p_colacion_mensual FROM dual;
*/

/* ---------- Limpieza (TRUNCATE) de tablas de proyección ---------- */
/*  */
TRUNCATE TABLE PROY_MOVILIZACION;
TRUNCATE TABLE BONIF_POR_UTILIDAD;
TRUNCATE TABLE USUARIO_CLAVE;
TRUNCATE TABLE HIST_ARRIENDO_ANUAL_CAMION;
TRUNCATE TABLE INFO_SII;

/* =====================================================================
   CARGA 1: PROY_MOVILIZACION
   Regla básica (ajustable por BIND):
   - valor_movil_normal = sueldo_base * :p_movil_pct/100
   - valor_movil_extra  = valor_movil_normal * :p_movil_extra_pct/100
   - valor_total_movil  = normal + extra
   ===================================================================== */
INSERT INTO PROY_MOVILIZACION
( anno_proceso, id_emp, numrun_emp, dvrun_emp, nombre_empleado,
  nombre_comuna, sueldo_base, porc_movil_normal, valor_movil_normal,
  valor_movil_extra, valor_total_movil )
SELECT
  :p_anno                                             AS anno_proceso,
  e.id_emp,
  e.numrun_emp,
  e.dvrun_emp,
  /* nombre_empleado (hasta 60) */
  SUBSTR(
    TRIM(
      e.pnombre_emp||' '||NVL(e.snombre_emp,'')||' '||e.appaterno_emp||' '||e.apmaterno_emp
    ),
  1, 60)                                              AS nombre_empleado,
  c.nombre_comuna,
  e.sueldo_base,
  :p_movil_pct                                        AS porc_movil_normal,
  TRUNC(e.sueldo_base * (:p_movil_pct/100))           AS valor_movil_normal,
  TRUNC(e.sueldo_base * (:p_movil_pct/100) * (:p_movil_extra_pct/100)) AS valor_movil_extra,
  TRUNC(e.sueldo_base * (:p_movil_pct/100)) +
  TRUNC(e.sueldo_base * (:p_movil_pct/100) * (:p_movil_extra_pct/100)) AS valor_total_movil
FROM EMPLEADO e
LEFT JOIN COMUNA c ON c.id_comuna = e.id_comuna;

COMMIT;

/* =====================================================================
   CARGA 2: BONIF_POR_UTILIDAD
   Supuesto razonable (ajustable): el bono por utilidad se basa en los
   años trabajados y en el porcentaje del TRAMO_ANTIGUEDAD vigente (:p_anno).
   Se calcula como: sueldo_base * meses_trab_en_el_año * (porcentaje/100).
   ===================================================================== */
INSERT INTO BONIF_POR_UTILIDAD
( anno_proceso, id_emp, sueldo_base, valor_bonif_utilidad )
SELECT
  :p_anno                                 AS anno_proceso,
  e.id_emp,
  e.sueldo_base,
  /* Bono por utilidad anual aproximado */
  TRUNC(
    e.sueldo_base *
    (CASE
      WHEN EXTRACT(YEAR FROM e.fecha_contrato) < :p_anno
           THEN 12
      ELSE GREATEST(1, 13 - EXTRACT(MONTH FROM e.fecha_contrato))
     END) *
    (t.porcentaje/100)
  )                                       AS valor_bonif_utilidad
FROM EMPLEADO e
JOIN TRAMO_ANTIGUEDAD t
  ON t.ANNO_VIG = :p_anno
 AND FLOOR(MONTHS_BETWEEN(TO_DATE('3112'||:p_anno,'DDMMYYYY'), e.fecha_contrato)/12)
     BETWEEN t.TRAMO_INF AND t.TRAMO_SUP;

COMMIT;

/* =====================================================================
   CARGA 3: USUARIO_CLAVE
   Generación simple:
   - nombre_usuario = primera letra pnombre + appaterno (máx. 20, minúsculas, sin espacios)
   - clave_usuario  = numrun_emp||dvrun_emp (máx. 20)
   ===================================================================== */
INSERT INTO USUARIO_CLAVE
( id_emp, numrun_emp, dvrun_emp, nombre_empleado, nombre_usuario, clave_usuario )
SELECT
  e.id_emp,
  e.numrun_emp,
  e.dvrun_emp,
  SUBSTR(TRIM(e.pnombre_emp||' '||NVL(e.snombre_emp,'')||' '||e.appaterno_emp||' '||e.apmaterno_emp),1,60) AS nombre_empleado,
  /* usuario: ej. jgonzalez */
  SUBSTR(LOWER(REGEXP_REPLACE(SUBSTR(e.pnombre_emp,1,1)||e.appaterno_emp,'\s+','')),1,20) AS nombre_usuario,
  SUBSTR(TO_CHAR(e.numrun_emp)||e.dvrun_emp,1,20)                                          AS clave_usuario
FROM EMPLEADO e;

COMMIT;

/* =====================================================================
   CARGA 4: HIST_ARRIENDO_ANUAL_CAMION
   - total_veces_arrendado = cantidad de arriendos del año :p_anno
   - Se arrastra valor_arriendo_dia y valor_garantia_dia desde CAMION
   Nota: La columna en HIST_ARRIENDO_ANUAL_CAMION es valor_garactia_dia (sic)
   ===================================================================== */
INSERT INTO HIST_ARRIENDO_ANUAL_CAMION
( anno_proceso, id_camion, nro_patente, valor_arriendo_dia, valor_garactia_dia, total_veces_arrendado )
SELECT
  :p_anno AS anno_proceso,
  c.id_camion,
  c.nro_patente,
  c.valor_arriendo_dia,
  c.valor_garantia_dia,   -- Mapea a "valor_garactia_dia" en la tabla destino
  COUNT(*) AS total_veces_arrendado
FROM ARRIENDO_CAMION a
JOIN CAMION c ON c.id_camion = a.id_camion
WHERE EXTRACT(YEAR FROM a.fecha_ini_arriendo) = :p_anno
GROUP BY
  c.id_camion, c.nro_patente, c.valor_arriendo_dia, c.valor_garantia_dia;

COMMIT;

/* =====================================================================
   CARGA 5: INFO_SII (construcción anual simplificada y coherente)
   Reglas asumidas (ajustables sin tocar INSERT, cambiando BINDs):
   - meses_trabajados: si contrato antes de :p_anno => 12; si en :p_anno => 13 - mes(contrato)
   - annos_trabajados: FLOOR(MONTHS_BETWEEN(fin_de_anno, fecha_contrato)/12)
   - sueldo_base_anual  = sueldo_base * meses_trabajados
   - bono_annos_anual   = sueldo_base_anual * (porcentaje tramo antigüedad / 100)
   - bono_especial_anual= sueldo_base_anual * (:p_bono_especial_pct/100)
   - movilizacion_anual = valor_total_movil (PROY) * meses_trabajados
   - colacion_anual     = :p_colacion_mensual * meses_trabajados
   - desctos_legales    = (sueldo_base_anual + bono_annos_anual + bono_especial_anual)
                          * ((porc_afp + porc_salud)/100)
   - sueldo_bruto_anual = sueldo_base_anual + bono_annos_anual + bono_especial_anual
                          + movilizacion_anual + colacion_anual
   - renta_imponible_anual = (sueldo_base_anual + bono_annos_anual + bono_especial_anual) - desctos_legales
     (Se excluye movilización y colación de imponible por criterio usual)
   ===================================================================== */
INSERT INTO INFO_SII
( anno_tributario, id_emp, run_empleado, nombre_empleado, cargo, meses_trabajados,
  annos_trabajados, sueldo_base_mensual, sueldo_base_anual, bono_annos_anual,
  bono_especial_anual, movilizacion_anual, colacion_anual, desctos_legales,
  sueldo_bruto_anual, renta_imponible_anual )
WITH base AS (
  SELECT
    e.id_emp,
    e.numrun_emp,
    e.dvrun_emp,
    TRIM(e.pnombre_emp||' '||NVL(e.snombre_emp,'')||' '||e.appaterno_emp||' '||e.apmaterno_emp) AS nombre_emp,
    e.sueldo_base,
    e.fecha_contrato,
    a.porc_descto_afp,
    s.porc_descto_salud,
    /* meses del año procesado */
    CASE
      WHEN EXTRACT(YEAR FROM e.fecha_contrato) < :p_anno THEN 12
      ELSE GREATEST(1, 13 - EXTRACT(MONTH FROM e.fecha_contrato))
    END AS meses_trab,
    /* años trabajados a fin de año procesado */
    FLOOR(MONTHS_BETWEEN(TO_DATE('3112'||:p_anno,'DDMMYYYY'), e.fecha_contrato)/12) AS annos_trab
  FROM EMPLEADO e
  JOIN AFP a         ON a.cod_afp = e.cod_afp
  JOIN TIPO_SALUD s  ON s.cod_tipo_sal = e.cod_tipo_sal
),
tramo AS (
  SELECT
    b.*,
    t.porcentaje AS pct_tramo
  FROM base b
  JOIN TRAMO_ANTIGUEDAD t
    ON t.ANNO_VIG = :p_anno
   AND b.annos_trab BETWEEN t.TRAMO_INF AND t.TRAMO_SUP
),
movil AS (
  SELECT
    p.id_emp,
    p.valor_total_movil
  FROM PROY_MOVILIZACION p
  WHERE p.anno_proceso = :p_anno
)
SELECT
  :p_anno AS anno_tributario,
  z.id_emp,
  TO_CHAR(z.numrun_emp)||'-'||z.dvrun_emp AS run_empleado,
  SUBSTR(z.nombre_emp,1,60)               AS nombre_empleado,
  :p_cargo_default                         AS cargo,
  z.meses_trab                             AS meses_trabajados,
  z.annos_trab                             AS annos_trabajados,
  z.sueldo_base                            AS sueldo_base_mensual,
  (z.sueldo_base * z.meses_trab)           AS sueldo_base_anual,
  /* bono por años (tramo) */
  TRUNC((z.sueldo_base * z.meses_trab) * (z.pct_tramo/100))               AS bono_annos_anual,
  /* bono especial anual (parametrizable) */
  TRUNC((z.sueldo_base * z.meses_trab) * (:p_bono_especial_pct/100))      AS bono_especial_anual,
  /* movilización y colación anuales */
  NVL(TRUNC(m.valor_total_movil * z.meses_trab),0)                         AS movilizacion_anual,
  TRUNC(:p_colacion_mensual * z.meses_trab)                                 AS colacion_anual,
  /* descuentos legales (AFP + Salud) sobre imponible */
  TRUNC(
    ((z.sueldo_base * z.meses_trab)
      + TRUNC((z.sueldo_base * z.meses_trab) * (z.pct_tramo/100))
      + TRUNC((z.sueldo_base * z.meses_trab) * (:p_bono_especial_pct/100)))
    * ((z.porc_descto_afp + z.porc_descto_salud)/100)
  )                                                                         AS desctos_legales,
  /* sueldo bruto anual (incluye no imponibles) */
  ((z.sueldo_base * z.meses_trab)
    + TRUNC((z.sueldo_base * z.meses_trab) * (z.pct_tramo/100))
    + TRUNC((z.sueldo_base * z.meses_trab) * (:p_bono_especial_pct/100))
    + NVL(TRUNC(m.valor_total_movil * z.meses_trab),0)
    + TRUNC(:p_colacion_mensual * z.meses_trab))                            AS sueldo_bruto_anual,
  /* renta imponible anual (criterio simple) */
  ((z.sueldo_base * z.meses_trab)
    + TRUNC((z.sueldo_base * z.meses_trab) * (z.pct_tramo/100))
    + TRUNC((z.sueldo_base * z.meses_trab) * (:p_bono_especial_pct/100)))
    - TRUNC(
        ((z.sueldo_base * z.meses_trab)
          + TRUNC((z.sueldo_base * z.meses_trab) * (z.pct_tramo/100))
          + TRUNC((z.sueldo_base * z.meses_trab) * (:p_bono_especial_pct/100)))
        * ((z.porc_descto_afp + z.porc_descto_salud)/100)
      )                                                                      AS renta_imponible_anual
FROM tramo z
LEFT JOIN movil m ON m.id_emp = z.id_emp;

COMMIT;

/* ================================
   Parámetro de pruebas (BIND)
   ================================ */
VAR p_anno NUMBER;
BEGIN
  :p_anno := EXTRACT(YEAR FROM SYSDATE);  -- año actual
END;
/

/* ============== EVIDENCIAS (corrida 1: año actual) ============== */
PROMPT ==== EVIDENCIAS: conteos con :p_anno ====
SELECT COUNT(*) AS filas_proy_movil FROM PROY_MOVILIZACION           WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_bonif      FROM BONIF_POR_UTILIDAD          WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_usrclave   FROM USUARIO_CLAVE;
SELECT COUNT(*) AS filas_hist_cam   FROM HIST_ARRIENDO_ANUAL_CAMION  WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_info_sii   FROM INFO_SII                    WHERE anno_tributario = :p_anno;

PROMPT ==== Muestras (top 5 filas) ====
SELECT *
FROM (
  SELECT * FROM PROY_MOVILIZACION WHERE anno_proceso = :p_anno ORDER BY id_emp
) WHERE ROWNUM <= 5;

SELECT *
FROM (
  SELECT * FROM INFO_SII WHERE anno_tributario = :p_anno ORDER BY id_emp
) WHERE ROWNUM <= 5;

/* ============== EVIDENCIAS (corrida 2: año anterior) ============== */
BEGIN
  :p_anno := EXTRACT(YEAR FROM SYSDATE) - 1;  -- año anterior
END;
/

PROMPT ==== Conteos año anterior con :p_anno ====
SELECT COUNT(*) AS filas_proy_movil FROM PROY_MOVILIZACION           WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_bonif      FROM BONIF_POR_UTILIDAD          WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_hist_cam   FROM HIST_ARRIENDO_ANUAL_CAMION  WHERE anno_proceso    = :p_anno;
SELECT COUNT(*) AS filas_info_sii   FROM INFO_SII                    WHERE anno_tributario = :p_anno;


