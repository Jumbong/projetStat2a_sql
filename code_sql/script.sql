-- Database: mimic

-- DROP DATABASE IF EXISTS mimic;
/*
CREATE DATABASE mimic
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'English_United States.1252'
    LC_CTYPE = 'English_United States.1252'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
*/	
/*CREATE OR REPLACE VIEW indiv_CPR AS
select *
FROM mimiciv_hosp.procedures_icd pro
WHERE pro.icd_code = '9960' or pro.icd_code = '9393';

CREATE OR REPLACE VIEW arret_c AS
select *
FROM mimiciv_hosp.diagnoses_icd dia
where dia.icd_code IN (SELECT icd_code
					FROM mimiciv_hosp.d_icd_diagnoses 
					WHERE LOWER(long_title) LIKE '%cardiac arrest%');
	
	
CREATE OR REPLACE VIEW rythme_nulle AS	
select * 
FROM mimiciv_icu.chartevents ch 
where  ch.itemid = 220045 and ch.value ='0';

select distinct count(1) from arret_c 
*/
/*
DROP VIEW IF EXISTS  CPR_inter_arretcardiaque;
CREATE VIEW CPR_inter_arretcardiaque AS
select indiv_cpr.subject_id,indiv_cpr.hadm_id,indiv_cpr.chartdate chartdate_cpr,
indiv_cpr.icd_code icd_code_cpr,arret_c.icd_code icd_code_diagno
from indiv_cpr
INNER JOIN arret_c 
ON indiv_cpr.subject_id=arret_c.subject_id and 
indiv_cpr.hadm_id=arret_c.hadm_id;*/

/* CREATE OR REPLACE VIEW rythmenulle_CPR AS
select subject_id,hadm_id from indiv_cpr
intersect 
select subject_id,hadm_id from rythme_nulle */

/*DROP VIEW IF EXISTS  CPR_inter_arretFinal;
CREATE OR REPLACE VIEW CPR_inter_arretFinal AS
select cir.subject_id, cir.hadm_id,pt.gender,pt.anchor_age,cir.chartdate_cpr, cir.icd_code_cpr,
cir.icd_code_diagno, pt.anchor_year, pt.anchor_year_group
from CPR_inter_arretcardiaque cir
INNER JOIN mimiciv_hosp.patients pt
ON cir.subject_id=pt.subject_id;*/

--Création des jours JO,J1,J2 et J3
/*
DROP VIEW IF EXISTS  CPR_inter_jour;
CREATE VIEW CPR_inter_jour AS
SELECT cir.subject_id, cir.hadm_id, pt.gender, pt.anchor_age, cir.chartdate_cpr, cir.icd_code_cpr,
       cir.icd_code_diagno, pt.anchor_year, pt.anchor_year_group,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '0 DAY') AS JO,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '1 DAY') AS J1,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '2 DAY') AS J2,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '2 DAY') AS J3
FROM CPR_inter_arretcardiaque cir
INNER JOIN mimiciv_hosp.patients pt
ON cir.subject_id = pt.subject_id;*/

-- Lactate
-- Lactate
/*CREATE TABLE CPR_lactate2 AS
select *
FROM mimiciv_hosp.labevents lab
where lab.itemid IN (SELECT itemid 
					FROM mimiciv_hosp.d_labitems 
					WHERE LOWER(label) LIKE '%lactate%' and fluid='Blood' and Category='Blood Gas')
;*/
/*
CREATE TABLE CPR_essai AS
SELECT cir.subject_id, cir.hadm_id, pt.gender, pt.anchor_age, cir.chartdate_cpr, cir.icd_code_cpr,
       cir.icd_code_diagno, pt.anchor_year, pt.anchor_year_group,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '0 DAY') AS JO,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '1 DAY') AS J1,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '2 DAY') AS J2,
       date(DATE_TRUNC('day', cir.chartdate_cpr) + INTERVAL '2 DAY') AS J3
FROM CPR_inter_arretcardiaque cir
INNER JOIN mimiciv_hosp.patients pt
ON cir.subject_id = pt.subject_id;


--Création de la table lactate_J0_final
DROP TABLE lactate_J0_final;
CREATE TABLE lactate_J0_final AS
SELECT CPR_lactate2.value,CPR_lactate2.subject_id,CPR_lactate2.hadm_id,
lactate_J0_date.max,CPR_lactate2.charttime
FROM lactate_J0_date,CPR_lactate2
	WHERE CPR_lactate2.subject_id=lactate_J0_date.subject_id AND 
	CPR_lactate2.hadm_id=lactate_J0_date.hadm_id AND 
	CPR_lactate2.charttime=(lactate_J0_date.max)
;


--Ajout de la variable lactate_JO

--ALTER TABLE CPR_essai ADD COLUMN lactate_JO_ VARCHAR(200);
UPDATE CPR_essai
SET lactate_JO = (
    SELECT lactate_J0_final.value
    FROM lactate_J0_final
    WHERE CPR_essai.subject_id = lactate_J0_final.subject_id 
        AND CPR_essai.hadm_id = lactate_J0_final.hadm_id 
        AND CPR_essai.JO = DATE(lactate_J0_final.charttime)
);

---- lactate J1
--Ajout de la variable lactate_J1
--ALTER TABLE CPR_essai ADD COLUMN lactate_J1 VARCHAR(200);
UPDATE CPR_essai
SET lactate_J1 = (
    SELECT lactate_J0_final.value
    FROM lactate_J0_final
    WHERE CPR_essai.subject_id = lactate_J0_final.subject_id 
        AND CPR_essai.hadm_id = lactate_J0_final.hadm_id 
        AND CPR_essai.J1 = DATE(lactate_J0_final.charttime)
);

---- lactate J2
--Ajout de la variable lactate_J2
--ALTER TABLE CPR_essai ADD COLUMN lactate_J2 VARCHAR(200);
UPDATE CPR_essai
SET lactate_J2 = (
    SELECT lactate_J0_final.value
    FROM lactate_J0_final
    WHERE CPR_essai.subject_id = lactate_J0_final.subject_id 
        AND CPR_essai.hadm_id = lactate_J0_final.hadm_id 
        AND CPR_essai.J2= DATE(lactate_J0_final.charttime)
);
---- lactate J3
--Ajout de la variable lactate_J3
--ALTER TABLE CPR_essai ADD COLUMN lactate_J3 VARCHAR(200);
UPDATE CPR_essai
SET lactate_J3 = (
    SELECT lactate_J0_final.value
    FROM lactate_J0_final
    WHERE CPR_essai.subject_id = lactate_J0_final.subject_id 
        AND CPR_essai.hadm_id = lactate_J0_final.hadm_id 
        AND CPR_essai.J3 = DATE(lactate_J0_final.charttime)
);


UPDATE CPR_essai
SET lactate_JO = REPLACE(lactate_JO, '___', '0');
UPDATE CPR_essai
SET lactate_J1 = REPLACE(lactate_J1, '___', '0');
UPDATE CPR_essai
SET lactate_J2 = REPLACE(lactate_J2, '___', '0');
UPDATE CPR_essai
SET lactate_J3 = REPLACE(lactate_J3, '___', '0');

CREATE TABLE base_travail AS 
			SELECT  * 
			FROM CPR_essai
			WHERE(
					 	(cast(CPR_essai.lactate_JO as float)>=2.0 or 
						cast(CPR_essai.lactate_J1 as float)>=2.0 or 
						cast(CPR_essai.lactate_J2 as float)>=2.0 or 
						cast(CPR_essai.lactate_J3 as float)>=2.0 )) 

--
--221289 et 229617 correspondent à l'epinephrine
SELECT * 
					FROM mimiciv_icu.d_items 
					WHERE LOWER(label) LIKE '%epinephrine%'

drop view V_individu_epinephrine;
create view V_individu_epinephrine as
select subject_id, hadm_id, sum(amount) amount_total,date(inputs.starttime) starttime_final
FROM mimiciv_icu.inputevents inputs
where inputs.itemid= 221289 or inputs.itemid= 229617
group by inputs.subject_id,inputs.hadm_id,date(inputs.starttime)

ALTER TABLE base_travail ADD COLUMN epinephrine_J0 double precision;
UPDATE base_travail
SET epinephrine_J0 = (
    SELECT amount_total
    FROM V_individu_epinephrine
    WHERE base_travail.subject_id = V_individu_epinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_epinephrine.hadm_id 
        AND base_travail.JO = V_individu_epinephrine.starttime_final
)

ALTER TABLE base_travail ADD COLUMN epinephrine_J1 double precision;
UPDATE base_travail
SET epinephrine_J1 = (
    SELECT amount_total
    FROM V_individu_epinephrine
    WHERE base_travail.subject_id = V_individu_epinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_epinephrine.hadm_id 
        AND base_travail.J1 = V_individu_epinephrine.starttime_final
)

ALTER TABLE base_travail ADD COLUMN epinephrine_J2 double precision;
UPDATE base_travail
SET epinephrine_J2 = (
    SELECT amount_total
    FROM V_individu_epinephrine
    WHERE base_travail.subject_id = V_individu_epinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_epinephrine.hadm_id 
        AND base_travail.J2 = V_individu_epinephrine.starttime_final
)

ALTER TABLE base_travail ADD COLUMN epinephrine_J3 double precision;
UPDATE base_travail
SET epinephrine_J1 = (
    SELECT amount_total
    FROM V_individu_epinephrine
    WHERE base_travail.subject_id = V_individu_epinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_epinephrine.hadm_id 
        AND base_travail.J3 = V_individu_epinephrine.starttime_final
)


-----Norepinephrine
--221906 correspond àu norepinephrine
SELECT * 
					FROM mimiciv_icu.d_items 
					WHERE LOWER(label) LIKE '%epinephrine%'

drop view if exists V_individu_norepinephrine;
create view V_individu_norepinephrine as
select subject_id, hadm_id, sum(amount) amount_total,date(inputs.starttime) starttime_final
FROM mimiciv_icu.inputevents inputs
where inputs.itemid= 221906
group by inputs.subject_id,inputs.hadm_id,date(inputs.starttime)

ALTER TABLE base_travail ADD COLUMN norepinephrine_J0 double precision;
UPDATE base_travail
SET norepinephrine_J0 = (
    SELECT amount_total
    FROM V_individu_norepinephrine
    WHERE base_travail.subject_id = V_individu_norepinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_norepinephrine.hadm_id 
        AND base_travail.JO = V_individu_norepinephrine.starttime_final
)
;
ALTER TABLE base_travail ADD COLUMN norepinephrine_J1 double precision;
UPDATE base_travail
SET norepinephrine_J1 = (
    SELECT amount_total
    FROM V_individu_norepinephrine
    WHERE base_travail.subject_id = V_individu_norepinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_norepinephrine.hadm_id 
        AND base_travail.J1 = V_individu_norepinephrine.starttime_final
);

ALTER TABLE base_travail ADD COLUMN norepinephrine_J2 double precision;
UPDATE base_travail
SET norepinephrine_J2 = (
    SELECT amount_total
    FROM V_individu_norepinephrine
    WHERE base_travail.subject_id = V_individu_norepinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_norepinephrine.hadm_id 
        AND base_travail.J2 = V_individu_norepinephrine.starttime_final
);

ALTER TABLE base_travail ADD COLUMN norepinephrine_J3 double precision;
UPDATE base_travail
SET norepinephrine_J3 = (
    SELECT amount_total
    FROM V_individu_norepinephrine
    WHERE base_travail.subject_id = V_individu_norepinephrine.subject_id 
        AND base_travail.hadm_id = V_individu_norepinephrine.hadm_id 
        AND base_travail.J3 = V_individu_norepinephrine.starttime_final
);
--221653 correspond au Dobutamine
SELECT * 
			FROM mimiciv_icu.d_items 
			WHERE LOWER(label) LIKE '%dobutamine%'
		
create view V_individu_dobutamine as
select subject_id, hadm_id, sum(amount) amount_total,date(inputs.starttime) starttime_final
FROM mimiciv_icu.inputevents inputs
where inputs.itemid= 221653
group by inputs.subject_id,inputs.hadm_id,date(inputs.starttime)
	
ALTER TABLE base_travail ADD COLUMN dobutamine_J0 double precision;
UPDATE base_travail
SET dobutamine_J0 = (
    SELECT amount_total
    FROM V_individu_dobutamine
    WHERE base_travail.subject_id = V_individu_dobutamine.subject_id 
        AND base_travail.hadm_id = V_individu_dobutamine.hadm_id 
        AND base_travail.JO = V_individu_dobutamine.starttime_final
)
;

ALTER TABLE base_travail ADD COLUMN dobutamine_J1 double precision;
UPDATE base_travail
SET dobutamine_J1 = (
    SELECT amount_total
    FROM V_individu_dobutamine
    WHERE base_travail.subject_id = V_individu_dobutamine.subject_id 
        AND base_travail.hadm_id = V_individu_dobutamine.hadm_id 
        AND base_travail.J1 = V_individu_dobutamine.starttime_final
)
;

ALTER TABLE base_travail ADD COLUMN dobutamine_J2 double precision;
UPDATE base_travail
SET dobutamine_J2 = (
    SELECT amount_total
    FROM V_individu_dobutamine
    WHERE base_travail.subject_id = V_individu_dobutamine.subject_id 
        AND base_travail.hadm_id = V_individu_dobutamine.hadm_id 
        AND base_travail.J2 = V_individu_dobutamine.starttime_final
)
;

ALTER TABLE base_travail ADD COLUMN dobutamine_J3 double precision;
UPDATE base_travail
SET dobutamine_J3 = (
    SELECT amount_total
    FROM V_individu_dobutamine
    WHERE base_travail.subject_id = V_individu_dobutamine.subject_id 
        AND base_travail.hadm_id = V_individu_dobutamine.hadm_id 
        AND base_travail.J3 = V_individu_dobutamine.starttime_final
)
;

--  221749 correspond à phenylephrine
SELECT * 
			FROM mimiciv_icu.d_items 
			WHERE LOWER(label) LIKE '%phenylephrine%'

create view V_individu_phenylephrine as
select subject_id, hadm_id, sum(amount) amount_total,date(inputs.starttime) starttime_final
FROM mimiciv_icu.inputevents inputs
where inputs.itemid= 221749
group by inputs.subject_id,inputs.hadm_id,date(inputs.starttime)

ALTER TABLE base_travail ADD COLUMN phenylephrine_J0 double precision;
UPDATE base_travail
SET phenylephrine_J0 = (
    SELECT amount_total
    FROM V_individu_phenylephrine
    WHERE base_travail.subject_id = V_individu_phenylephrine.subject_id 
        AND base_travail.hadm_id = V_individu_phenylephrine.hadm_id 
        AND base_travail.JO = V_individu_phenylephrine.starttime_final
)
;
ALTER TABLE base_travail ADD COLUMN phenylephrine_J1 double precision;
UPDATE base_travail
SET phenylephrine_J1 = (
    SELECT amount_total
    FROM V_individu_phenylephrine
    WHERE base_travail.subject_id = V_individu_phenylephrine.subject_id 
        AND base_travail.hadm_id = V_individu_phenylephrine.hadm_id 
        AND base_travail.J1 = V_individu_phenylephrine.starttime_final
)
;

ALTER TABLE base_travail ADD COLUMN phenylephrine_J2 double precision;
UPDATE base_travail
SET phenylephrine_J2 = (
    SELECT amount_total
    FROM V_individu_phenylephrine
    WHERE base_travail.subject_id = V_individu_phenylephrine.subject_id 
        AND base_travail.hadm_id = V_individu_phenylephrine.hadm_id 
        AND base_travail.J2 = V_individu_phenylephrine.starttime_final
)
;

ALTER TABLE base_travail ADD COLUMN phenylephrine_J3 double precision;
UPDATE base_travail
SET phenylephrine_J3 = (
    SELECT amount_total
    FROM V_individu_phenylephrine
    WHERE base_travail.subject_id = V_individu_phenylephrine.subject_id 
        AND base_travail.hadm_id = V_individu_phenylephrine.hadm_id 
        AND base_travail.J3 = V_individu_phenylephrine.starttime_final
)
;
*/	
ALTER TABLE base_travail ADD COLUMN catecholamine varchar(1);
UPDATE base_travail
SET catecholamine= 
	CASE
		WHEN (phenylephrine_J3=null and phenylephrine_J2=null and phenylephrine_J1=null and phenylephrine_J0=null and 
			epinephrine_J0=null and epinephrine_J1=null and epinephrine_J2=null and epinephrine_J3=null and 
			norepinephrine_J0=null and norepinephrine_J1=null and norepinephrine_J2=null and norepinephrine_J3=null and 
			dobutamine_J0=null and dobutamine_J1=null and dobutamine_J2=null and dobutamine_J3=null ) then '0'
		ELSE '1'
	END
;	
SElect count(*) FROM base_travail where catecholamine='1'
