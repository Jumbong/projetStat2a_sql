/*Création de la vue 'V_ind_ayant_CPR' qui recupère tous les individus qui ont la procédure CPR*/
CREATE OR REPLACE VIEW V_ind_ayant_CPR AS
    SELECT DISTINCT pro.subject_id, min(pro.hadm_id) hadm_id,
	pro.chartdate datedebut
    FROM mimiciv_hosp.procedures_icd pro
    WHERE pro.icd_code = '9960' 
	GROUP BY pro.subject_id,pro.chartdate
;

/*Création de la vue 'V_individus_ayant_AC' qui recupère tous les individus dont le cardiac arrest apparait dans leur diagnostics en 
privant les itemid qui correspondent à l'arrêt cardiaque du nouveau né*/

CREATE OR REPLACE VIEW V_individus_ayant_AC AS
    SELECT DISTINCT *
    FROM mimiciv_hosp.diagnoses_icd dia
    WHERE dia.icd_code IN (SELECT icd_code
                        FROM mimiciv_hosp.d_icd_diagnoses 
                        WHERE LOWER(long_title) LIKE '%cardiac arrest%'
                        AND icd_code !='77985' AND icd_code !='P2981')
;



/*On veut créer une variable qui récupère le jour où le patient a eu son arret cardiaque . Pour cela, pour les individus qui ont eu 
la procédure 'CardioPulmonaire reanimation, le jour de la procédure correspond au jour de l'arret et ce dernier est renseigné dans la
variable 'chardate' renommée 'datedebut' dans la vue 'V_ind_ayant_CPR' . Pour les individus qui ont eu l'arret cardiac et qui 
n'apparaissent pas dans les patients ayant eu la procédure 'CPR', le jour de l'arret cardiaque du patient correspond au jour de leur 
admission*/

--Jointure entre la table admission et les individus ayant le diagnostic 'cardiac arrest' afin de récupérer la date d'admission
CREATE OR REPLACE VIEW V_admission_AR AS
    SELECT DISTINCT var.subject_id,var.hadm_id,
	date(adm.admittime) datedebut
	FROM V_individus_ayant_AC var
	INNER JOIN mimiciv_hosp.admissions adm
	ON adm.subject_id=var.subject_id AND adm.hadm_id=var.hadm_id
;
	
/*Une fois, la liste des individus ayant le diagnostic 'Cardiac arrest' obtenue, on recupére grace au mot clé min, 
le premier séjour du patient. En effet, un patient peut revenir plusieurs fois à l'hopital. Pour un tel patient, son id sera
intacte mais l'id de son admission et sa date d'arrivée vont changer.*/    
CREATE OR REPLACE VIEW V_admission_ayant_AR AS
    SELECT subject_id,min(hadm_id) hadm_id,datedebut
    FROM V_admission_AR
    GROUP BY subject_id, datedebut
;


/* Vus qu'il est possible que certains patients aient à la fois la procédure 'CPR' et le mot 'cardiac arrest dans leur diagnostic,
l'on récupère, dans cette partie, les individus qui ont juste l'arret cardiac sans la CPR (jointure left join avec where key null)*/
CREATE OR REPLACE VIEW V_DIA_prive_CPR AS
	SELECT DISTINCT ar.subject_id,ar.hadm_id,ar.datedebut
	FROM V_admission_ayant_AR ar
	LEFT JOIN V_ind_ayant_CPR cpr 
	ON ar.subject_id=cpr.subject_id AND ar.hadm_id=cpr.hadm_id 
	WHERE cpr.subject_id IS NULL and cpr.hadm_id is NULL
;    

/* A cet instant, on a la vue 'V_DIA_prive_CPR' qui regroupe les séjours des patients qui ont eu uniquement le diagnostic
'cardiac arrest' et la vue qui regroupe les séjours pendant lesquels les patients ont eu la procedure 'CPR'. Dans cette 
partie,nous faisons une union de ces deux vues en y ajoutant une variable origin qui précise l'origine de la table*/
CREATE OR REPLACE VIEW V_FINAL_AR AS
	SELECT  *,'AR' as origin 
	FROM V_DIA_prive_CPR
	UNION 
	SELECT  * ,'CPR' as origin
	FROM V_ind_ayant_CPR 
;

/*On cherche à créer une table qui sélectionne les premiers séjours. On fait l'hypothèse que pour un patient qui a eu plusieurs séjours, 
le premier séjour doit etre celui qui a la date la plus petite. Cette table nous permet,donc, de récuperer l'id du patient
et la date du 1er arret cardiaque*/
CREATE TABLE T_Final_distinct AS
    SELECT V_FINAL_AR.subject_id,min(V_FINAL_AR.datedebut) datedebut
    FROM V_FINAL_AR
    GROUP BY V_FINAL_AR.subject_id
;
/* Création de la vue 'V_Final_distinct' qui fait une jointure entre la liste des premiers séjours et la table regroupant 
tous les séjours des patients pendant lesquels ils ont eu l'arret cardiaque*/
CREATE VIEW V_Final_distinct AS
    SELECT V_FINAL_AR.* 
    FROM V_FINAL_AR 
    INNER JOIN T_Final_distinct
    ON V_FINAL_AR.subject_id=T_Final_distinct.subject_id AND V_FINAL_AR.datedebut=T_Final_distinct.datedebut
;
/* après avoir eu la liste des premiers séjours aucours desquels, les patients ont eu l'arret cardiaque, on fait une jointure entre 
cette liste contenue dans la vue 'V_Final_distinct' et la table 'patients' dans le but de récuperer en plus de l'id des patients, l'id des
1er séjour pendant lesquels ils ont eu l'arret cardiaque, la date de l'arret cardiaque, le sexe, l'age, le groupe d'année. On y crée aussi
les variables J0, J1, J2 et J3 qui correspondent respectivement aux date de l'arrêt cardiaque, au lendemain de l'arrêt cardiaque,
au surlendemain de l'arrêt et au jour suivant le surlendemain de l'arrêt cardiaque */
CREATE OR REPLACE VIEW V_patient_ayant_AR AS
    SELECT cir.subject_id, cir.hadm_id,pt.gender,pt.anchor_age,cir.datedebut,
    pt.anchor_year, pt.anchor_year_group,
    date(DATE_TRUNC('day', cir.datedebut) + INTERVAL '0 DAY') AS J0,
    date(DATE_TRUNC('day', cir.datedebut) + INTERVAL '1 DAY') AS J1,
    date(DATE_TRUNC('day', cir.datedebut) + INTERVAL '2 DAY') AS J2,
    date(DATE_TRUNC('day', cir.datedebut) + INTERVAL '2 DAY') AS J3
    FROM V_Final_distinct cir
    INNER JOIN mimiciv_hosp.patients pt
    ON cir.subject_id=pt.subject_id 
;

--********************************************************************************************************************************--
                                                        /*EXTRACTION DES VARIABLES */
--********************************************************************************************************************************--

----------------------------------------------------------------------------------------------------------------------
                                                    /*Lactate*/
/* Les mesures de lactate correspondent à toutes les lignes de la table 'labevents' ayant pour valeur de la variable
itemid 50813 ou 52442*/                                                    
----------------------------------------------------------------------------------------------------------------------
--On crée la vue 'V_mesurelactate' qui recupère toutes les mesures de lactate de tous les séjours des patients
CREATE OR REPLACE VIEW V_mesurelactate AS
    SELECT *
    FROM mimiciv_hosp.labevents lab
    WHERE lab.itemid in (50813,52442)
;

--On recupere dans la variable value_max, la valeur maximale de lactate pour un patient pendant un jour donné. En effet, la vue 
--'V_mesurelactate' est telle que si dans une même journée, on fait plusieurs mesures de lactate à des heures differentes,
--chaque de ces mesures constituera une ligne de la vue 'V_mesurelactate'.

CREATE OR REPLACE VIEW V_lactate AS
    SELECT max(V_mesurelactate.valuenum) value_max,
    V_mesurelactate.subject_id,date(V_mesurelactate.charttime) charttime
    FROM V_mesurelactate
    GROUP BY V_mesurelactate.subject_id, date(V_mesurelactate.charttime)
;

--Création de la vue 'lactate_0' qui recupère pour tous les individus ayant eu l'arrêt cardique, la valeur maximale de lactate le jour
--de leur arrêt cardiaque.(Il s'agit d'une jointure entre V_patient_ayant_ar et V_lactate lorsque les id des patients coincident et 
--lorque le jour du prélevement correspond au jour de l'arrêt cardiaque:J0). 
--Cette valeur maximale est stockée dans la variable "lactate_J0(mmol/L)"

CREATE OR REPLACE VIEW lactate_0 as select V_patient_ayant_ar.*, 
V_lactate.value_max "lactate_J0(mmol/L)"
    FROM V_patient_ayant_ar
    LEFT JOIN V_lactate
    ON V_lactate.subject_id = V_patient_ayant_ar.subject_id
    WHERE V_lactate.charttime = V_patient_ayant_ar.J0
;

--Création de la vue 'lactate_1' qui recupère pour tous les individus ayant eu l'arrêt cardique, la valeur maximale de lactate le lendemain
--de leur arrêt cardiaque.(Il s'agit d'une jointure entre V_patient_ayant_ar et V_lactate lorsque les id des patients coincident et 
--lorque le jour du prélevement correspond au jour suivant l'arrêt cardiaque:J1)
--Cette valeur maximale est stockée dans la variable "lactate_J1(mmol/L)"

CREATE OR REPLACE VIEW lactate_1 as select V_patient_ayant_ar.*,V_lactate.value_max "lactate_J1(mmol/L)"
    FROM V_patient_ayant_ar
    LEFT JOIN V_lactate
    ON V_lactate.subject_id = V_patient_ayant_ar.subject_id
    WHERE V_lactate.charttime = V_patient_ayant_ar.J1
;

--Tout comme lactate_1 et lactate_0, on récupere dans lactate_2, la valeur maximale de lactate mesurée pour les patients ayant eu l'arrêt
--cardiaque deux jours après l'arret cardiaque dans la variable "lactate_J2(mmol/L)".

CREATE OR REPLACE VIEW lactate_2 as select V_patient_ayant_ar.*,V_lactate.value_max "lactate_J2(mmol/L)"
    FROM V_patient_ayant_ar
    LEFT JOIN V_lactate
    ON V_lactate.subject_id = V_patient_ayant_ar.subject_id
    WHERE V_lactate.charttime = V_patient_ayant_ar.J2
;

--Tout comme lactate_1, lactate_0 et lactate_2 on récupere dans lactate_3, la valeur maximale de lactate mesurée pour les patients ayant eu l'arrêt
--cardiaque trois jours après l'arret cardiaque dans la variable "lactate_J3(mmol/L)".
CREATE OR REPLACE VIEW lactate_3 as select V_patient_ayant_ar.*,V_lactate.value_max "lactate_J3(mmol/L)"
    FROM V_patient_ayant_ar
    LEFT JOIN V_lactate
    ON V_lactate.subject_id = V_patient_ayant_ar.subject_id
    WHERE V_lactate.charttime = V_patient_ayant_ar.J3
;

/*Après avoir récupéré dans lactate_0, lactate_1, lactate_2 et lactate_3 respectivement les mesures maximale de lactate des individus
ayant eu l'arret cardiaque le jour le l'arrêt, le lendemain, deux jours et trois jours aprés l'arrêt cardiaque;on crée la vue 'lactate_B0'
qui fait une jointure gauche entre les vues 'V_patient_ayant_ar' et 'lactate_0' dans le but de conserver tous les éléments de la
vue 'V_patient_ayant_ar' et d'y ajouter la variable "lactate_J0(mmol/L)" de la vue 'lactate_0'. Dans cette nouvelle table, tous les
patients à qui on a effectué au moins une mesure de lactate le jour de leur arret cardiaque auront la valeur maximale de lactate 
stockée dans la variable "lactate_J0(mmol/L)". Cependant, les patients auxquelles aucune mesure de lactate n'a été faite le jour de leur
arrêt cardiaque (c'est-a-dire les patients qui ne se trouvent pas dans 'lactate_0') auront comme valeur de la variable "lactate_J0(mmol/L)"
'NULL' */

CREATE OR REPLACE VIEW lactate_B0 AS 
    SELECT V_patient_ayant_ar.*, lactate_0."lactate_J0(mmol/L)"
    FROM V_patient_ayant_ar
    LEFT JOIN lactate_0
    ON lactate_0.subject_id = V_patient_ayant_ar.subject_id
;

/*Une fois que la vue 'lactate_B0' contenant les variables comme l'age, le sexe, le jour de l'arret cardiaque ainsi que la valeur 
maximale de lactate le jour de l'arrêt cardiaque a été créée, nous effectuons une jointure entre cette vue et la vue 'lactate_1' 
pour récuperer toutes les variables de la vue 'lactate_B0' et la variable "lactate_J1(mmol/L)" de la vue 'lactate_1'.Ainsi, tous les 
patients qui n'ont aucune mesure de lactate le lendemain de leur arrêt cardiaque auront une valeur de "lactate_J1(mmol/L)"='NULL' et 
ceux à qui on a fait des prelevements à J1 auront la valeur maximale de toutes les mesures effectuées le lendemain de l'arret cardiaque 
comme valeur de "lactate_J1(mmol/L)"*/

CREATE OR REPLACE VIEW lactate_B1 AS
    SELECT lactate_B0.*, lactate_1."lactate_J1(mmol/L)"
    FROM lactate_B0
    LEFT JOIN lactate_1
    ON lactate_1.subject_id = lactate_B0.subject_id
;

/*Une fois que la vue 'lactate_B1' contenant les variables démographiques des patients, le jour de l'arret cardiaque ainsi que 
les variables "lactate_J0(mmol/L)" et "lactate_J1(mmol/L)", nous effectuons une jointure entre cette vue et la vue 'lactate_2' 
pour récuperer toutes les variables de la vue 'lactate_B1' et la variable "lactate_J2(mmol/L)" de la vue 'lactate_2'.Ainsi, tous 
les patients qui n'ont aucune mesure de lactate deux jours après leurs arrêt cardiaque auront une valeur de "lactate_J2(mmol/L)"='NULL' 
et ceux à qui on a fait des prelevements auront la valeur maximale de toutes les mesures effectuées le lendemain de l'arret cardiaque 
comme valeur de "lactate_J2(mmol/L)"*/

CREATE OR REPLACE VIEW lactate_B2 AS
    SELECT lactate_B1.*, lactate_2."lactate_J2(mmol/L)"
    FROM lactate_B1
    LEFT JOIN lactate_2
    ON lactate_2.subject_id = lactate_B1.subject_id
;
/*Sur le principe de création de la vue 'lactate_B2', nous crééons la vue 'lactate_B3' qui n'est juste qu'une jointure entre
la vue 'lactate_B2' et la vue 'lactate_3' afin d'ajouter aux variables de la vue 'lactate_B2', la variable "lactate_J3(mmol/L)". Ainsi,
tous les patients qui n'ont aucune mesure de lactate trois jours après leurs arrêt cardiaque auront une valeur de "lactate_J3(mmol/L)" 
'NULL' et ceux à qui on a fait des prelevements trois jours après leurs arrêt cardiaque auront la valeur maximale de toutes les mesures 
effectuées trois jours après leurs arrêt cardiaque comme valeur de "lactate_J3(mmol/L)"*/
CREATE OR REPLACE VIEW lactate_B3 AS
    SELECT lactate_B2.*, lactate_3."lactate_J3(mmol/L)"
    FROM lactate_B2
    LEFT JOIN lactate_3
    ON lactate_3.subject_id = lactate_B2.subject_id
;

/*Ayant les mesures maximales de lactate à J0(jour de l'arrêt cardiaque), à J1(le jour suivant l'arrêt cardiaque),
à J2(deux jours après l'arrêt cardiaque) et à J3 (trois jours après l'arrêt cardiaque), nous sélectionnons les individus ayant
eu au moins une mesure de lactate supérieur à 2 duarant les trois jours ayant suivis leur arrêt cardiaque.
En d'autres termes, les individus qui sont tels que soit "lactate_J0(mmol/L)">=2, soit "lactate_J1(mmol/L)">=2 , 
soit "lactate_J2(mmol/L)">=2 ou "lactate_J3(mmol/L)">=2. Ces individus sont stockés dans la table 'T_final_lactate'*/

CREATE TABLE T_final_lactate AS 
    SELECT * FROM lactate_B3 
    WHERE 
        (cast(lactate_B3."lactate_J0(mmol/L)" as float) >= 2.0 or 
        cast(lactate_B3."lactate_J1(mmol/L)" as float) >= 2.0 or 
        cast(lactate_B3."lactate_J2(mmol/L)" as float) >= 2.0 or 
        cast(lactate_B3."lactate_J3(mmol/L)" as float) >= 2.0 )
;        

/*Note : Nous continuerons notre selection pour les individus qui ont eu l'arrêt cardiaque et qui durant les trois jours qui ont suivi
leur arrêt cardiaque, ont eu au moins une mesure de lactate supérieure à 2 autrement dit les individus de la table 'T_final_lactate'). 
La table 'T_final_lactate' contient les variables suivantes :
            --subject_id : l'id du patient
            --hadm_id    : l'id de l'admission
            --datedebut   : le jour de l'arret cardiaque
            --J0        : le jour de l'arret cardiaque
            --J1        :le jour suivant l'arret cardiaque
            --J2        :deux jours après l'arret cardiaque
            --J3        :trois jours après l'arret cardiaque
            --age       :age du patient
            --gender    :le sexe du patient
            --anchor_age
            --anchor_year : l'année d'admission anchor_year
            --anchor_group_year : le groupe d'année qui correspond 
            --"lactate_J0(mmol/L)" : la valeur maximale de lactate de J0
            --"lactate_J1(mmol/L)" : la valeur maximale de lactate de J1
            --"lactate_J2(mmol/L)" : la valeur maximale de lactate de J2
            --"lactate_J3(mmol/L)" : la valeur maximale de lactate de J3
*/
----------------------------------------------------------------------------------------------------------------------
                                                    /*Ph*/
----------------------------------------------------------------------------------------------------------------------
--Nous devons sélectionner la moyenne journalière de ph par patient
/*Tout d'abord, on récurepère toutes les mesures de ph pour tous les patients quelque soit leurs maux. Ces mesures se trouvent dans la
table 'labevents' et correspondent aux lignes pour lesquelles l'itemid = 50820(l'itemid de ph)*/

--Nous créeons ici, une vue 'V_mesureph' qui regroupe toutes ces mesures
CREATE OR REPLACE VIEW V_mesureph AS
    SELECT *
    FROM mimiciv_hosp.labevents lab
    WHERE lab.itemid = 50820 ;

-- La vue 'V_mesureph' contenant toutes les mesures de ph, nous résumons les informations relatives au patient et au jour du prélevement.
-- En effet, telle que la vue 'V_mesureph' se présente, si on a eu faire plusieurs prélevements de ph aux patients à differents moments
-- d'une journée, chacune de ces mesures sera enrégistrée et sera donc une ligne de la vue 'V_mesureph'. Nous prenons la moyenne
-- journalière par patient(cette moyenne est matérialisée par avg:average(V_mesureph.valuenum) group by V_mesureph.subject_id, 
-- date(V_mesureph.charttime)) que nous stockons dans la variable 'value_moyen'

CREATE OR REPLACE VIEW V_ph AS
    SELECT AVG(V_mesureph.valuenum) value_moyen,V_mesureph.subject_id,date(V_mesureph.charttime) charttime
    FROM V_mesureph
    GROUP BY V_mesureph.subject_id, date(V_mesureph.charttime)
;
/*Ensuite, nous effectuons la jointure entre la vue V_mesureph et la table 'T_final_lactate' qui contient la liste des individus 
ayant eu un arrêt cardiaque durant leur premier séjour à l'hôpital et au moins une mesure de lactate supérieur à 2 durant les 
trois jours qui ont suivi leur arrêt cardiaque. */

--plus précisément nous avons créé 'ph_0' qui récupère pour chaque patient la valeur de ph moyenne lorsque des mesures de ph ont été 
--effectuées le jour de l’arrêt cardiaque et nous stockons ces valeurs dans la variable 'phlabevents_J0'
CREATE OR REPLACE VIEW ph_0 
AS SELECT T_final_lactate.*,V_ph.value_moyen "phlabevents_J0"
    FROM T_final_lactate
    LEFT JOIN V_ph
    ON V_ph.subject_id = T_final_lactate.subject_id
    WHERE V_ph.charttime = T_final_lactate.J0
;

/*Sur le même ordre d'idées, nous créeons la vue 'ph_1' qui regroupe pour l'ensemble des individus ayant eu l'arrêt cardiaque et 
ayant eu une mesure de lactate supérieure ou égal à 2 durant les 3 premiers jours ayant suivi leur arrêt cardiaque, les mesures moyennes 
de ph lorsque ces prélevements coïncident avec J1 (lendemain de l'arret cardiaque). Ces valeurs sont stockés dans la variable
'phlabevents_J1'. */
CREATE OR REPLACE VIEW ph_1 
AS SELECT T_final_lactate.*,V_ph.value_moyen "phlabevents_J1"
    FROM T_final_lactate
    LEFT JOIN V_ph
    ON V_ph.subject_id = T_final_lactate.subject_id
    WHERE V_ph.charttime = T_final_lactate.J1
;

/*Tout comme les vues 'ph_0' et 'ph_1',la vue 'ph_2' est créée de sorte qu'elle soit une jointure entre la table 'T_final_lactate' et 
la vue 'V_ph' regroupant l'ensemble des mesures moyennes de ph effectuées à J2(deux jours après l'arrêt cardiaque).
Ces valeurs sont stockés dans la variable 'phlabevents_J2'*/
CREATE OR REPLACE VIEW ph_2 as select T_final_lactate.*,V_ph.value_moyen "phlabevents_J2"
    FROM T_final_lactate
    LEFT JOIN V_ph
    ON V_ph.subject_id = T_final_lactate.subject_id
    WHERE V_ph.charttime = T_final_lactate.J2
;

/*Tout comme les vues 'ph_0','ph_1' et 'ph_2' la vue 'ph_3' est créée de sorte qu'elle soit une jointure entre la table 'T_final_lactate' et 
la vue 'V_ph' regroupant l'ensemble des mesures moyennes de ph effectuées à J3(trois jours après l'arrêt cardiaque). 
Ces valeurs sont stockés dans la variable 'phlabevents_J3'. */
CREATE OR REPLACE VIEW ph_3 as select T_final_lactate.*,V_ph.value_moyen "phlabevents_J3"
    FROM T_final_lactate
    LEFT JOIN V_ph
    ON V_ph.subject_id = T_final_lactate.subject_id
    WHERE V_ph.charttime = T_final_lactate.J3
;

/*Dans cette partie, nous avons créé la vue 'ph_B0' qui en plus de la table 'T_final_lactate' contient la variable 'phlabevents_J0' de la 
vue 'ph_0' de sorte que si des mesures de ph ont été éffectuées pour un individu à J0, 'phlabevents_J0' soit égale à la moyenne de cet 
individus et pour des individus n'ayant pas de mesures de ph à J0, 'phlabevents_J0' prenne la valeur 'NULL'*/

CREATE OR REPLACE VIEW ph_B0 AS 
    SELECT T_final_lactate.*, ph_0."phlabevents_J0"
    FROM T_final_lactate
    LEFT JOIN ph_0
    ON ph_0.subject_id = T_final_lactate.subject_id
;

/*Nous avons créé la vue 'ph_B1' qui est une jointure gauche entre 'ph_B0' et la vue 'ph_1'. Cette vue contient ainsi tous les élements
 de la table 'T_final_lactate' et les variables 'phlabevents_J0' et 'phlabevents_J1'.Notons que pour les individus de 'T_final_lactate'
 n'ayant pas eu de mesures de ph à leur J1(le jour suivant l'arrêt cardiaque), la variable 'phlabevents_J1' prend la valeur 'NULL'. */

CREATE OR REPLACE VIEW ph_B1 AS
    SELECT ph_B0.*, ph_1."phlabevents_J1"
    FROM ph_B0
    LEFT JOIN ph_1
    ON ph_1.subject_id = ph_B0.subject_id
;

/*Nous avons créé la vue 'ph_B2' qui est une jointure gauche entre ph_B1 et 'ph_2' afin de récupérer toutes les variables de la vue 
'ph_B1' et la variable 'phlabevents_J2' de la vue 'ph_2'. Cette vue contient ainsi tous les élements de la table 'T_final_lactate' et 
les variables 'phlabevents_J0', 'phlabevents_J1' et phlabevents_J2'.Notons que pour les individus n'ayant pas eu de mesures de ph à
leur J2(deux jours après l'arrêt cardiaque), la variable 'phlabevents_J2' prendra la valeur 'NULL'.*/

CREATE OR REPLACE VIEW ph_B2 AS
    SELECT ph_B1.*, ph_2."phlabevents_J2"
    FROM ph_B1
    LEFT JOIN ph_2
    ON ph_2.subject_id = ph_B1.subject_id
;

/*La vue 'ph_B3' est une jointure gauche pour récupérer tous les enregistements de la vue 'ph_B2' et la variable 'phlabevents_J3' de
la vue 'ph_3'. Cette vue contient ainsi tous les élements de la table 'T_final_lactate' et les variables 'phlabevents_J0', '
phlabevents_J1', phlabevents_J2' et  'phlabevents_J3'. Notons que pour les individus n'ayant pas eu de mesures de ph à leur 
J3(trois jours après l'arrêt cardiaque), la variable 'phlabevents_J3' prendra la valeur 'NULL'.*/
CREATE OR REPLACE VIEW ph_B3 AS
    SELECT ph_B2.*, ph_3."phlabevents_J3"
    FROM ph_B2
    LEFT JOIN ph_3
    ON ph_3.subject_id = ph_B2.subject_id
;

--On récupère dans la table 'T_final_lactate_ph' tous les individus ayant eu l'arrêt cardiaque et ayant eu une mesure de lactate 
--supérieure à 2, les variables de la table 'T_final_lactate' et les variables "phlabevents_J0" ,"phlabevents_J1" ,"phlabevents_J2"  
-- et "phlabevents_J3" 

CREATE TABLE T_final_lactate_ph AS 
    SELECT T_final_lactate.*
    ,ph_B3."phlabevents_J0" 
    ,ph_B3."phlabevents_J1" 
    ,ph_B3."phlabevents_J2" 
    ,ph_B3."phlabevents_J3" 
    FROM T_final_lactate 
    LEFT JOIN ph_B3
    ON T_final_lactate.subject_id = ph_B3.subject_id
;

----------------------------------------------------------------------------------------------------------------------
                                                    /*Temperature*/
----------------------------------------------------------------------------------------------------------------------
/* La table ' d_labitems' décrit les itemid des variables contenues dans 'labevents'. Nous recherchons les 
itemid de catégory 'Blood Gas' , de type de fluid 'blood' et dont le label contient le mot 'température'. Ensuite, nous recherchons 
dans la table 'labevents' toutes les lignes dont les itemid se trouvent dans la liste d'itemid trouvée plus haut.*/     


--Nous créeons ici, une vue 'V_mesuretemperature' qui regroupe toutes les mesures de température

CREATE OR REPLACE VIEW V_mesuretemperature AS
    SELECT *
    FROM mimiciv_hosp.labevents lab
    WHERE lab.itemid IN (SELECT itemid 
                        FROM mimiciv_hosp.d_labitems 
                        WHERE LOWER(label) LIKE '%temperature%' and fluid='Blood' and Category='Blood Gas')
;


-- Après la création de la vue 'V_mesuretemperature' qui contient toutes les mesures de temperature, nous allons résumer les informations
-- relatives au patient et au jour des prélevements.En effet, telle que la vue 'V_mesuretemperature' se présente, si on a fait plusieurs 
--mesure de temperature à un patient à differents moments d'une journée, chacune de ces mesures sera enrégistrée et sera donc une ligne de
--la vue 'V_mesuretemperature'. Par conséquent, nous prenons la valeur maximale journalière par patient que nous stockons dans la 
--variable 'value_max'

CREATE OR REPLACE VIEW V_temperature AS
    SELECT max(V_mesuretemperature.valuenum) value_max,
    V_mesuretemperature.subject_id,date(V_mesuretemperature.charttime) charttime
    FROM V_mesuretemperature
    GROUP BY V_mesuretemperature.subject_id, date(V_mesuretemperature.charttime)
;

/*Ensuite, nous effectuons la jointure entre la vue 'V_temperature' et la table 'T_final_lactate' qui contient la liste des individus 
ayant eu un arrêt cardiaque et ayant eu au moins une mesure de lactate supérieur à 2 durant les trois jours qui ont suivi leur arrêt 
cardiaque. 

Plus précisément nous avons créé temperature_0 qui récupère pour chaque patient sa valeur de temperature maximale si des prises de températures
ont été effectuées le jour de son arrêt cardiaque et nous stockons ces valeurs dans la variable 'temperaturelabevents_J0'.Ensuite, nous créons
la variable 'indicatrice_temperature_J0' qui indique si durant le jour de son arrêt cardiaque, le patient a eu à être en 
hyperthermie(température >37.7)
*/

CREATE OR REPLACE VIEW temperature_0 
AS SELECT T_final_lactate.*
    ,V_temperature.value_max temperaturelabevents_J0
    ,(CASE
        WHEN(cast(V_temperature.value_max as float)>37.7) then '1'
        ELSE '0'
    END) AS indicatrice_temperature_J0
    FROM T_final_lactate
    LEFT JOIN V_temperature
    ON V_temperature.subject_id = T_final_lactate.subject_id
    WHERE V_temperature.charttime = T_final_lactate.J0
;

/*De même, nous créeons la vue 'temperature_1' qui regroupe pour l'ensemble des individus ayant eu un arrêt cardiaque et ayant eu une 
mesure de lactate supérieure ou égal à 2 durant les 3 premiers jours ayant suivi leur arrêt cardiaque, les mesures maximales de
 temperature lorsque ces prélevements coïncident avec J1 (lendemain de l'arret cardiaque). Ces valeurs sont stockés dans la variable
'temperaturelabevents_J1'. Ensuite, la variable 'indicatrice_temperature_J1' a été créée pour indiquer si le patient a été en 
hyperthermie à J1*/

CREATE OR REPLACE VIEW temperature_1 
AS SELECT T_final_lactate.*
    ,V_temperature.value_max temperaturelabevents_J1
    ,(CASE
        WHEN(cast(V_temperature.value_max as float)>37.7) then '1'
        ELSE '0'
    END) AS indicatrice_temperature_J1
    FROM T_final_lactate
    LEFT JOIN V_temperature
    ON V_temperature.subject_id = T_final_lactate.subject_id
    WHERE V_temperature.charttime = T_final_lactate.J1
;

/*Tout comme les vues 'temperature_0' et 'temperature_1' ,la vue 'temperature_2' est créée de sorte à ce qu'elle soit une jointure 
entre la table 'T_final_lactate' et la vue 'V_temperature' regroupant l'ensemble des temperatures maximale effectuées à 
J2(deux jours après l'arrêt cardiaque).
Ces valeurs sont stockés dans la variable 'temperaturelabevents_J2'. la variable 'indicatrice_temperature_J2' a été créée pour 
indiquer si le patient a été en hyperthermie à J2*/

CREATE OR REPLACE VIEW temperature_2 as select T_final_lactate.*
    ,V_temperature.value_max temperaturelabevents_J2
    ,(CASE
        WHEN(cast(V_temperature.value_max as float)>37.7) then '1'
        ELSE '0'
    END) AS indicatrice_temperature_J2
    FROM T_final_lactate
    LEFT JOIN V_temperature
    ON V_temperature.subject_id = T_final_lactate.subject_id
    WHERE V_temperature.charttime = T_final_lactate.J2
;

-- 'temperaturelabevents_J3' et 'indicatrice_temperature_J3' ont été créée de la même manière que les variables temperaturelabevents_J1',
-- 'indicatrice_temperature_J1',temperaturelabevents_J2' et 'indicatrice_temperature_J2'
CREATE OR REPLACE VIEW temperature_3 as select T_final_lactate.*
,V_temperature.value_max temperaturelabevents_J3
,(CASE
        WHEN(cast(V_temperature.value_max as float)>37.7) then '1'
        ELSE '0'
    END) AS indicatrice_temperature_J3
    FROM T_final_lactate
    LEFT JOIN V_temperature
    ON V_temperature.subject_id = T_final_lactate.subject_id
    WHERE V_temperature.charttime = T_final_lactate.J3
;

--------Jointures
/*Dans cette partie, nous avons créé la vue 'temperature_B0' qui en plus de la table 'T_final_lactate' contient les variables 
'temperaturelabevents_J0' et indicatrice_temperature_J0 de la vue 'temperature_0' de sorte que si des mesures de temperature ont été 
éffectuées pour un individu à J0, 'temperaturelabevents_J0' soit égale au maximum des températures de ces individus et 
pour des individus pour lesquelles des mesures de temperature n'ont pas été faite à J0, 
'temperaturelabevents_J0' prenne la valeur 'NULL'. 
De même, si des patients auxquels des prises de températures ont été faites à J0 et qui n'ont pas été en hyperthermie,
la variaable 'indicatrice_temperature_J0' prendra 0. Mais pour les patients auxquelles aucune température n'a été prise à J0, 
la variable 'indicatrice_temperature_J0' sera égale à 'NULL'. */

CREATE OR REPLACE VIEW temperature_B0 AS 
    SELECT T_final_lactate.*
    , temperature_0.temperaturelabevents_J0
    , temperature_0.indicatrice_temperature_J0
    FROM T_final_lactate
    LEFT JOIN temperature_0
    ON temperature_0.subject_id = T_final_lactate.subject_id
;

/*Nous avons créé la vue 'temperature_B1' qui est une jointure la vue 'temperature_B0' et de la vue 'temperature_1'. Cette vue contient 
ainsi tous les élements de la table 'T_final_lactate', les variables 'temperaturelabevents_J0', 'indicatrice_temperature_J0' de la vue 
'temperature_B0' et les variables 'temperaturelabevents_J1', 'indicatrice_temperature_J1' de la vue 'temperature_1'. Notons que pour 
les individus n'ayant pas eu de mesures de temperature à leur J1(le jour suivant l'arrêt cardiaque), 
les variables 'temperaturelabevents_J1' et 'indicatrice_temperature_J1' prendront la valeur 'NULL'. */

CREATE OR REPLACE VIEW temperature_B1 AS
    SELECT temperature_B0.*
    , temperature_1.temperaturelabevents_J1
    , temperature_1.indicatrice_temperature_J1
    FROM temperature_B0
    LEFT JOIN temperature_1
    ON temperature_1.subject_id = temperature_B0.subject_id 
;

/*Puis, nous avons créé la vue 'temperature_B2' qui est une jointure la vue 'temperature_B1' et de la vue 'temperature_2'.Cette vue 
contient ainsi tous les élements de la table 'T_final_lactate', les variables 'temperaturelabevents_J0', 'indicatrice_temperature_J0'
de la vue 'temperature_B0'; les variables 'temperaturelabevents_J1', 'indicatrice_temperature_J1' de la vue 'temperature_1' et les 
variables 'temperaturelabevents_J2', 'indicatrice_temperature_J2' de la vue 'temperature_2'. 
Notons que pour les individus n'ayant pas eu de mesures de temperature à leur J2(le jour suivant l'arrêt cardiaque), 
les variables 'temperaturelabevents_J2' et 'indicatrice_temperature_J2' prendront la valeur 'NULL'. */

CREATE OR REPLACE VIEW temperature_B2 AS
    SELECT temperature_B1.*
    , temperature_2.temperaturelabevents_J2
    , temperature_2.indicatrice_temperature_J2
    FROM temperature_B1
    LEFT JOIN temperature_2
    ON temperature_2.subject_id = temperature_B1.subject_id
;

/*la vue ci-dessous 'temperature_B3' est une jointure la vue 'temperature_B1' et de la vue 'temperature_2'. Elle contient ainsi tous 
les élements de la table 'T_final_lactate', les variables 'temperaturelabevents_J0', 'indicatrice_temperature_J0' de la vue 
'temperature_B0'; les variables 'temperaturelabevents_J1', 'indicatrice_temperature_J1' de la vue 'temperature_1' , les variables 
'temperaturelabevents_J2', 'indicatrice_temperature_J2' de la vue 'temperature_2' et les variables 'temperaturelabevents_J3', 
'indicatrice_temperature_J3' de la vue 'temperature_3'. Notons que pour les individus n'ayant pas eu de mesures de temperature à leur 
J3(le jour suivant l'arrêt cardiaque), les variables 'temperaturelabevents_J3' et 'indicatrice_temperature_J3' prendront la valeur 'NULL'. */


CREATE OR REPLACE VIEW temperature_B3 AS
    SELECT temperature_B2.*
    , temperature_3.temperaturelabevents_J3
    , temperature_3.indicatrice_temperature_J3
    FROM temperature_B2
    LEFT JOIN temperature_3
    ON temperature_3.subject_id = temperature_B2.subject_id
;


CREATE TABLE T_final_lactate_temperature AS 
    SELECT T_final_lactate_ph.*
    ,temperature_B3.temperaturelabevents_J0
    ,temperature_B3.temperaturelabevents_J1
    ,temperature_B3.temperaturelabevents_J2 
    ,temperature_B3.temperaturelabevents_J3 
    ,temperature_B3.indicatrice_temperature_J0
    ,temperature_B3.indicatrice_temperature_J1
    ,temperature_B3.indicatrice_temperature_J2
    ,temperature_B3.indicatrice_temperature_J3
    FROM T_final_lactate_ph 
    LEFT JOIN temperature_B3
    ON T_final_lactate_ph.subject_id = temperature_B3.subject_id
;

--On récupère dans la table 'T_base_final' tous les individus ayant eu un arrêt cardiaque et ayant eu une mesure de lactate 
--supérieure à 2,les variables "phlabevents_J0" ,"phlabevents_J1" ,"phlabevents_J2" ,"phlabevents_J3", "temperaturelabevents_J0" ,
--"temperaturelabevents_J1" ,"temperaturelabevents_J2" , "temperaturelabevents_J3" ,'indicatrice_temperature_J0',
--'indicatrice_temperature_J1','indicatrice_temperature_J2' et 'indicatrice_temperature_J3'

CREATE TABLE T_base_final AS 
    SELECT * 
    FROM T_final_lactate_temperature
;

/*Les catécholamines sont des substances qui sont données aux patients à differents taux(debit) et pendant des durées de temps differents.
Pour un patient, lorsque le taux ou le debit change, une nouvelle ligne apparait dans la table 'inputevents'
*/

----------------------------------------------------------------------------------------------------------------------
                                                    /*Epinephrine*/
----------------------------------------------------------------------------------------------------------------------
/*L'épinephrine correspond aux enrégistrements de la table 'inputevents' pour lesquelles la valeur de l'itemid est soit égale à 221289
 ou 229617. Voila pourquoi, la vue 'V_mesureepinephrine' a été créée pour contenir toutes les administrations d'épinephrines. */

CREATE OR REPLACE VIEW V_mesureepinephrine AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid IN (221289, 229617)
;

/*Les débits sont en mcg/Kg/min. Pour un patient ayant eu durant la même journée plusieurs administrations d'epinephrine à des taux 
differents, nous devons récupérer la moyenne par jour et par patient. Il s'agit d'une moyenne pondéré par le temps d'administration de
l'épinephrine.C'est ce qui explique la création de la vue 'V_epinephr' qui contient en plus des variables de la 'V_mesureepinephrine', la variable 
duree_minutes qui fait la difference entre les variables starttime(renseigne sur la date et l'heure de debut de l'administration) et 
endtime(renseigne sur la date et l'heure de fin de l'administration). La fonction "extract" de sql donne la difference en seconde. En 
divisant par 60, on rapporte la difference en minutes.*/

CREATE OR REPLACE VIEW V_epinephr AS
    SELECT V_mesureepinephrine.*,
    (EXTRACT(epoch FROM V_mesureepinephrine.endtime - V_mesureepinephrine.starttime))/60 AS duree_minutes
    FROM V_mesureepinephrine
;

-- Ayant la durée en minutes pendant laquelle l'administration a été effectuée, on la multiplie par le taux de sorte à avoir la quantité
-- totale d'épinephrine donnée au patient. Cette quantité est stockée dans la variable 'mesure_mcg_kg'
CREATE OR REPLACE VIEW V_epinephrine AS
    SELECT V_epinephr.*,
    (V_epinephr.duree_minutes*V_epinephr.rate) mesure_mcg_kg
    FROM V_epinephr
;

--Ensuite, on crée la vue 'V_epinephrine_final' qui contient pour un patient et un jour donnés, la quantité totale d'epinephrine qui lui
--a été administrée et la durée totale de toutes ces administrations
CREATE OR REPLACE VIEW V_epinephrine_final AS
    SELECT sum(V_epinephrine.mesure_mcg_kg) sum_epinephrine,
            sum(duree_minutes) duree_patientjour,
            V_epinephrine.subject_id,
            date(V_epinephrine.starttime) starttime
    FROM V_epinephrine
    GROUP BY V_epinephrine.subject_id, date(V_epinephrine.starttime)
;


/*Pour créer la variable "epinephrine_J0(mcg/Kg/min)", on divise la quantité totale d'épinephrine de J0 par la durée totale 
d'administration à J0. Cette variable est stockée dans la vue 'epinephrine_0'. 
Cette vue est en effet une jointure gauche entre 'T_final_lactate' et 'V_epinephrine_final'. A cet effet, elle contient les 
informations des patients qui ont eu un arrêt cardiaque et à qui on a administré l'épinephrine le jour de leur arrêt cardiaque.*/

CREATE OR REPLACE VIEW epinephrine_0 as select T_final_lactate.*
,V_epinephrine_final.sum_epinephrine/(V_epinephrine_final.duree_patientjour) AS "epinephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_epinephrine_final
    ON V_epinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_epinephrine_final.starttime = T_final_lactate.J0
;

/*Pour créer la variable "epinephrine_J1(mcg/Kg/min)", on divise la quantité totale d'épinephrine de J0 par 24*60. les 24 sont dues au
nombre d'heures que compte une journée et les 60 au fait qu'une heure équivaut à 60 minutes. Ainsi, la variable 
"epinephrine_J1(mcg/Kg/min)" a pour unité mcg/Kg/min. Cette variable est stockée dans la vue 'epinephrine_1'. Cette vue est en effet une
 jointure gauche entre 'T_final_lactate' et 'V_epinephrine_final' lorsque J1 est égale au jour de l'épinephrine */

CREATE OR REPLACE VIEW epinephrine_1 AS 
SELECT T_final_lactate.*
,V_epinephrine_final.sum_epinephrine/(24*60) AS "epinephrine_J1(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_epinephrine_final
    ON V_epinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_epinephrine_final.starttime = T_final_lactate.J1
;

/*La variable "epinephrine_J2(mcg/Kg/min)" de la vue 'epinephrine_2' a été créé sur le même principe que la variable 
"epinephrine_J1(mcg/Kg/min)". La vue 'epinephrine_2' contient les informations des patients qui ont eu un arrêt cardiaque et auxquels
l'on a administré de l'épinephrine deux jours après leur arrêt cardiaque*/

CREATE OR REPLACE VIEW epinephrine_2 AS 
SELECT T_final_lactate.*
,V_epinephrine_final.sum_epinephrine/(24*60) AS "epinephrine_J2(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_epinephrine_final
    ON V_epinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_epinephrine_final.starttime = T_final_lactate.J2
;

/*La variable "epinephrine_J23(mcg/Kg/min)" de la vue 'epinephrine_3 a été créé sur le même principe que les variables
"epinephrine_J1(mcg/Kg/min)" et "epinephrine_J2(mcg/Kg/min)". La vue 'epinephrine_2' contient les informations des patients qui ont 
eu un arrêt cardiaque et auxquels de l'épinephrine a été administrée trois jours après leur arrêt cardiaque*/

CREATE OR REPLACE VIEW epinephrine_3 AS 
SELECT T_final_lactate.*
,V_epinephrine_final.sum_epinephrine/(24*60) AS "epinephrine_J3(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_epinephrine_final
    ON V_epinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_epinephrine_final.starttime = T_final_lactate.J3
;

/*Dans cette partie, on fait une jointure entre la table 'T_final_lactate' et la vue 'epinephrine_0' de sorte à récupérer 
tout le contenu de la table 'T_final_lactate' et la variable "epinephrine_J0(mcg/Kg/min)" de la vue epinephrine_0. 
Si dans la table 'T_final_lactate', il y a des patients qui n'ont pas recu d'épinephrine à J0, la valeur de la variable 
"epinephrine_J0(mcg/Kg/min)" pour ces derniers sera égale à 'NULL' */
CREATE OR REPLACE VIEW epinephrine_B0 AS 
    SELECT T_final_lactate.*, epinephrine_0."epinephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN epinephrine_0
    ON epinephrine_0.subject_id = T_final_lactate.subject_id
;
/*De même, nous avons crée la vue 'epinephrine_B1' qui est une jointure entre les vues 'epinephrine_B0' et 'epinephrine_1' de sorte à 
récupérer tout le contenu de la vue 'epinephrine_B0' et la variable "epinephrine_J1(mcg/Kg/min)" de la vue epinephrine_1. Par conséquent,
en plus des lignes de 'T_final_lactate', la vue 'epinephrine_B1' contient les variables "epinephrine_J0(mcg/Kg/min)" et
"epinephrine_J1(mcg/Kg/min)". Cependant, si dans la table 'T_final_lactate', il y a des patients qui n'ont pas recu d'épinephrine à J1, 
la valeur de la variable "epinephrine_J1(mcg/Kg/min)" pour ces derniers sera égale à NULL */
CREATE OR REPLACE VIEW epinephrine_B1 AS 
    SELECT epinephrine_B0.*, epinephrine_1."epinephrine_J1(mcg/Kg/min)"
    FROM epinephrine_B0
    LEFT JOIN epinephrine_1
    ON epinephrine_1.subject_id = epinephrine_B0.subject_id
;

/*De même, nous avons crée la vue 'epinephrine_B2' qui est une jointure entre les vues 'epinephrine_B1' et 'epinephrine_2' de sorte à 
récupérer tout le contenu de la vue 'epinephrine_B1' et la variable "epinephrine_J2(mcg/Kg/min)" de la vue epinephrine_2. Par conséquent,
en plus des lignes de 'T_final_lactate', la vue 'epinephrine_B2' contient les variables "epinephrine_J0(mcg/Kg/min)",
"epinephrine_J1(mcg/Kg/min)" et "epinephrine_J2(mcg/Kg/min)". Cependant, si dans la table 'T_final_lactate', il y a des patients qui 
n'ont pas recu d'épinephrine à J2, leur valeur de "epinephrine_J2(mcg/Kg/min)" sera égale à NULL */

CREATE OR REPLACE VIEW epinephrine_B2 AS 
    SELECT epinephrine_B1.*, epinephrine_2."epinephrine_J2(mcg/Kg/min)"
    FROM epinephrine_B1
    LEFT JOIN epinephrine_2
    ON epinephrine_2.subject_id = epinephrine_B1.subject_id
;

/*De même, nous avons crée la vue 'epinephrine_B3' qui est une jointure entre les vues 'epinephrine_B2' et 'epinephrine_3' de sorte à 
récupérer tout le contenu de la vue 'epinephrine_B2' et la variable "epinephrine_J3(mcg/Kg/min)" de la vue epinephrine_3. 
Par conséquent,en plus des lignes de 'T_final_lactate', la vue 'epinephrine_B3' contient les variables "epinephrine_J0(mcg/Kg/min)", 
"epinephrine_J1(mcg/Kg/min)", "epinephrine_J2(mcg/Kg/min)" et "epinephrine_J3(mcg/Kg/min)". Cependant, si dans la table 'T_final_lactate',
il y a des patients qui n'ont pas recu d'épinephrine à J2, la valeur de la variable "epinephrine_J2(mcg/Kg/min)" pour ces derniers sera
 égale à NULL */
CREATE OR REPLACE VIEW epinephrine_B3 AS 
    SELECT epinephrine_B2.*, epinephrine_3."epinephrine_J3(mcg/Kg/min)"
    FROM epinephrine_B2
    LEFT JOIN epinephrine_3
    ON epinephrine_3.subject_id = epinephrine_B2.subject_id
;

/*En somme, on crée une table 'T_final_epinephrine' qui contient tous les individus ayant eu l'arrêt cardiaque et ayant eu une mesure
de lactate supérieure à 2, les variables "phlabevents_J0" ,"phlabevents_J1" ,"phlabevents_J2", "phlabevents_J3", 
temperaturelabevents_J0,indicatrice_temperature_J0,temperaturelabevents_J1,indicatrice_temperature_J1,temperaturelabevents_J2,
indicatrice_temperature_J2,temperaturelabevents_J3,indicatrice_temperature_J3,"epinephrine_J0(mcg/Kg/min)"
,"epinephrine_J1(mcg/Kg/min)","epinephrine_J2(mcg/Kg/min)","epinephrine_J3(mcg/Kg/min)" .*/
CREATE TABLE T_final_epinephrine AS 
    SELECT T_base_final.*
    ,epinephrine_B3."epinephrine_J0(mcg/Kg/min)"
    ,epinephrine_B3."epinephrine_J1(mcg/Kg/min)"
    ,epinephrine_B3."epinephrine_J2(mcg/Kg/min)"
    ,epinephrine_B3."epinephrine_J3(mcg/Kg/min)"
    FROM T_base_final 
    LEFT JOIN epinephrine_B3
    ON T_base_final.subject_id = epinephrine_B3.subject_id
;   
----------------------------------------------------------------------------------------------------------------------
                                                    /*Dopamine*/
----------------------------------------------------------------------------------------------------------------------
/*les variables "dopamine_J0(mcg/Kg/min)","dopamine_J1(mcg/Kg/min)","dopamine_J2(mcg/Kg/min)",
"dopamine_J3(mcg/Kg/min)" renseignants sur les quantités de dopamine administrées au patient
à J0, J1,J2 et J3 sont construites sur le même preincipe que les variables de la section
d'epinephrine. Dans un premier temps, on récupère toutes les mesures de dopamine dans la vue 'V_mesuredopamine'*
Ensuite, on ramene le taux d'administration(mcg/Kg/min) en mcg/Kg en multipliant par la durée d'administation
puis en divisant la durée totale d'administation du dopimine lorsqu'on est à J0 ou en en divisant par (24*60) 
lorsqu'on est à J1, J2 et J3.*/

CREATE OR REPLACE VIEW V_mesuredopamine AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =221662
;

CREATE OR REPLACE VIEW V_dopam AS
    SELECT V_mesuredopamine.*,
    (EXTRACT(epoch FROM V_mesuredopamine.endtime - V_mesuredopamine.starttime))/60 AS duree_minutes
    FROM V_mesuredopamine
;

CREATE OR REPLACE VIEW V_dopamine AS
    SELECT V_dopam.*,
    (V_dopam.duree_minutes*V_dopam.rate) mesure_mcg_kg
    FROM V_dopam
;

CREATE OR REPLACE VIEW V_dopamine_final AS
    SELECT sum(V_dopamine.mesure_mcg_kg) sum_dopamine,
            sum(duree_minutes) duree_patientjour,
            V_dopamine.subject_id,
            date(V_dopamine.starttime) starttime
    FROM V_dopamine
    GROUP BY V_dopamine.subject_id, date(V_dopamine.starttime)
;

CREATE OR REPLACE VIEW dopamine_0 as select T_final_lactate.*
,V_dopamine_final.sum_dopamine/(V_dopamine_final.duree_patientjour) AS "dopamine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dopamine_final
    ON V_dopamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dopamine_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW dopamine_1 AS 
SELECT T_final_lactate.*
,V_dopamine_final.sum_dopamine/(24*60) AS "dopamine_J1(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dopamine_final
    ON V_dopamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dopamine_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW dopamine_2 AS 
SELECT T_final_lactate.*
,V_dopamine_final.sum_dopamine/(24*60) AS "dopamine_J2(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dopamine_final
    ON V_dopamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dopamine_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW dopamine_3 AS 
SELECT T_final_lactate.*
,V_dopamine_final.sum_dopamine/(24*60) AS "dopamine_J3(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dopamine_final
    ON V_dopamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dopamine_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW dopamine_B0 AS 
    SELECT T_final_lactate.*, dopamine_0."dopamine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN dopamine_0
    ON dopamine_0.subject_id = T_final_lactate.subject_id
;
CREATE OR REPLACE VIEW dopamine_B1 AS 
    SELECT dopamine_B0.*, dopamine_1."dopamine_J1(mcg/Kg/min)"
    FROM dopamine_B0
    LEFT JOIN dopamine_1
    ON dopamine_1.subject_id = dopamine_B0.subject_id
;

CREATE OR REPLACE VIEW dopamine_B2 AS 
    SELECT dopamine_B1.*, dopamine_2."dopamine_J2(mcg/Kg/min)"
    FROM dopamine_B1
    LEFT JOIN dopamine_2
    ON dopamine_2.subject_id = dopamine_B1.subject_id
;

CREATE OR REPLACE VIEW dopamine_B3 AS 
    SELECT dopamine_B2.*, dopamine_3."dopamine_J3(mcg/Kg/min)"
    FROM dopamine_B2
    LEFT JOIN dopamine_3
    ON dopamine_3.subject_id = dopamine_B2.subject_id
;

CREATE TABLE T_final_dopamine AS 
    SELECT T_final_epinephrine.*
    ,dopamine_B3."dopamine_J0(mcg/Kg/min)"
    ,dopamine_B3."dopamine_J1(mcg/Kg/min)"
    ,dopamine_B3."dopamine_J2(mcg/Kg/min)"
    ,dopamine_B3."dopamine_J3(mcg/Kg/min)"
    FROM T_final_epinephrine 
    LEFT JOIN dopamine_B3
    ON T_final_epinephrine.subject_id = dopamine_B3.subject_id
;   
----------------------------------------------------------------------------------------------------------------------
                                                    /*Norepinephrine*/
----------------------------------------------------------------------------------------------------------------------
/*les variables "norepinephrine_J0(mcg/Kg/min)","norepinephrine_J1(mcg/Kg/min)","norepinephrine_J2(mcg/Kg/min)",
"norepinephrine_J3(mcg/Kg/min)" renseignants sur les quantités de norepinephrine administrées au patient
à J0, J1,J2 et J3 sont construites sur le même preincipe que les variables de la section
d'epinephrine. Dans un premier temps, on récupère toutes les mesures de norepinephrine dans la vue 'V_mesurenorepinephrine'*
Ensuite, on ramene le taux d'administration(mcg/Kg/min) en mcg/Kg en multipliant par la durée d'administation
puis en divisant la durée totale d'administation du dopimine lorsqu'on est à J0 ou en en divisant par (24*60) 
lorsqu'on est à J1, J2 et J3.*/

CREATE OR REPLACE VIEW V_mesurenorepinephrine AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =221906
;


CREATE OR REPLACE VIEW V_norepinephr AS
    SELECT V_mesurenorepinephrine.*,
    (EXTRACT(epoch FROM V_mesurenorepinephrine.endtime - V_mesurenorepinephrine.starttime))/60 AS duree_minutes
    FROM V_mesurenorepinephrine
;


CREATE OR REPLACE VIEW V_norepinephrine AS
    SELECT V_norepinephr.*,
    (V_norepinephr.duree_minutes*V_norepinephr.rate) AS mesure_mcg_kg
    FROM V_norepinephr
;


CREATE OR REPLACE VIEW V_norepinephrine_final AS
    SELECT sum(V_norepinephrine.mesure_mcg_kg) sum_norepinephrine,
            sum(duree_minutes) duree_patientjour,
            V_norepinephrine.subject_id,
            date(V_norepinephrine.starttime) starttime
    FROM V_norepinephrine
    GROUP BY V_norepinephrine.subject_id, date(V_norepinephrine.starttime)
;

CREATE OR REPLACE VIEW norepinephrine_0 as select T_final_lactate.*
,V_norepinephrine_final.sum_norepinephrine/(V_norepinephrine_final.duree_patientjour) AS "norepinephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_norepinephrine_final
    ON V_norepinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_norepinephrine_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW norepinephrine_1 AS 
SELECT T_final_lactate.*
,V_norepinephrine_final.sum_norepinephrine/(24*60) AS "norepinephrine_J1(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_norepinephrine_final
    ON V_norepinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_norepinephrine_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW norepinephrine_2 AS 
SELECT T_final_lactate.*
,V_norepinephrine_final.sum_norepinephrine/(24 *60) AS "norepinephrine_J2(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_norepinephrine_final
    ON V_norepinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_norepinephrine_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW norepinephrine_3 AS 
SELECT T_final_lactate.*
,V_norepinephrine_final.sum_norepinephrine/(24*60) AS "norepinephrine_J3(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_norepinephrine_final
    ON V_norepinephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_norepinephrine_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW norepinephrine_B0 AS 
    SELECT T_final_lactate.*, norepinephrine_0."norepinephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN norepinephrine_0
    ON norepinephrine_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW norepinephrine_B1 AS 
    SELECT norepinephrine_B0.*, norepinephrine_1."norepinephrine_J1(mcg/Kg/min)"
    FROM norepinephrine_B0
    LEFT JOIN norepinephrine_1
    ON norepinephrine_1.subject_id = norepinephrine_B0.subject_id
;

CREATE OR REPLACE VIEW norepinephrine_B2 AS 
    SELECT norepinephrine_B1.*, norepinephrine_2."norepinephrine_J2(mcg/Kg/min)"
    FROM norepinephrine_B1
    LEFT JOIN norepinephrine_2
    ON norepinephrine_2.subject_id = norepinephrine_B1.subject_id
;

CREATE OR REPLACE VIEW norepinephrine_B3 AS 
    SELECT norepinephrine_B2.*, norepinephrine_3."norepinephrine_J3(mcg/Kg/min)"
    FROM norepinephrine_B2
    LEFT JOIN norepinephrine_3
    ON norepinephrine_3.subject_id = norepinephrine_B2.subject_id
;

CREATE TABLE T_final_norepine AS 
    SELECT T_final_dopamine.*
    ,norepinephrine_B3."norepinephrine_J0(mcg/Kg/min)"
    ,norepinephrine_B3."norepinephrine_J1(mcg/Kg/min)"
    ,norepinephrine_B3."norepinephrine_J2(mcg/Kg/min)"
    ,norepinephrine_B3."norepinephrine_J3(mcg/Kg/min)"
    FROM T_final_dopamine 
    LEFT JOIN norepinephrine_B3
    ON T_final_dopamine.subject_id = norepinephrine_B3.subject_id
;  


----------------------------------------------------------------------------------------------------------------------
                                                    /*Dobutamine*/
----------------------------------------------------------------------------------------------------------------------
/*les variables "dobutamine_J0(mcg/Kg/min)","dobutamine_J1(mcg/Kg/min)","dobutamine_J2(mcg/Kg/min)",
"dobutamine_J3(mcg/Kg/min)" renseignants sur les quantités de dobutamine administrées au patient
à J0, J1,J2 et J3 sont construites sur le même preincipe que les variables de la section
d'epinephrine. Dans un premier temps, on récupère toutes les mesures de dobutamine dans la vue 'V_mesuredobutamine'*
Ensuite, on ramene le taux d'administration(mcg/Kg/min) en mcg/Kg en multipliant par la durée d'administation
puis en divisant la durée totale d'administation du dopimine lorsqu'on est à J0 ou en en divisant par (24*60) 
lorsqu'on est à J1, J2 et J3.*/

CREATE OR REPLACE VIEW V_mesuredobutamine AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =221653
;

CREATE OR REPLACE VIEW V_dobutam AS
    SELECT V_mesuredobutamine.*,
    (EXTRACT(epoch FROM V_mesuredobutamine.endtime - V_mesuredobutamine.starttime))/60 AS duree_minutes
    FROM V_mesuredobutamine
;

CREATE OR REPLACE VIEW V_dobutamine AS
    SELECT V_dobutam.*,
    (V_dobutam.duree_minutes*V_dobutam.rate) AS mesure_mcg_kg
    FROM V_dobutam
;


CREATE OR REPLACE VIEW V_dobutamine_final AS
    SELECT sum(V_dobutamine.mesure_mcg_kg) sum_dobutamine,
            sum(duree_minutes) duree_patientjour,
            V_dobutamine.subject_id,
            date(V_dobutamine.starttime) starttime
    FROM V_dobutamine
    GROUP BY V_dobutamine.subject_id, date(V_dobutamine.starttime)
;

CREATE OR REPLACE VIEW dobutamine_0 as select T_final_lactate.*
,V_dobutamine_final.sum_dobutamine/(V_dobutamine_final.duree_patientjour) AS "dobutamine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dobutamine_final
    ON V_dobutamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dobutamine_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW dobutamine_1 AS 
SELECT T_final_lactate.*
,V_dobutamine_final.sum_dobutamine/(24*60) AS "dobutamine_J1(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dobutamine_final
    ON V_dobutamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dobutamine_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW dobutamine_2 AS 
SELECT T_final_lactate.*
,V_dobutamine_final.sum_dobutamine/(24*60) AS "dobutamine_J2(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dobutamine_final
    ON V_dobutamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dobutamine_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW dobutamine_3 AS 
SELECT T_final_lactate.*
,V_dobutamine_final.sum_dobutamine/(24*60) AS "dobutamine_J3(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_dobutamine_final
    ON V_dobutamine_final.subject_id = T_final_lactate.subject_id
    WHERE V_dobutamine_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW dobutamine_B0 AS 
    SELECT T_final_lactate.*, dobutamine_0."dobutamine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN dobutamine_0
    ON dobutamine_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW dobutamine_B1 AS 
    SELECT dobutamine_B0.*, dobutamine_1."dobutamine_J1(mcg/Kg/min)"
    FROM dobutamine_B0
    LEFT JOIN dobutamine_1
    ON dobutamine_1.subject_id = dobutamine_B0.subject_id
;

CREATE OR REPLACE VIEW dobutamine_B2 AS 
    SELECT dobutamine_B1.*, dobutamine_2."dobutamine_J2(mcg/Kg/min)"
    FROM dobutamine_B1
    LEFT JOIN dobutamine_2
    ON dobutamine_2.subject_id = dobutamine_B1.subject_id
;
CREATE OR REPLACE VIEW dobutamine_B3 AS 
    SELECT dobutamine_B2.*, dobutamine_3."dobutamine_J3(mcg/Kg/min)"
    FROM dobutamine_B2
    LEFT JOIN dobutamine_3
    ON dobutamine_3.subject_id = dobutamine_B2.subject_id
;

CREATE TABLE T_final_dobutamine AS 
    SELECT T_final_norepine.*
    ,dobutamine_B3."dobutamine_J0(mcg/Kg/min)"
    ,dobutamine_B3."dobutamine_J1(mcg/Kg/min)"
    ,dobutamine_B3."dobutamine_J2(mcg/Kg/min)"
    ,dobutamine_B3."dobutamine_J3(mcg/Kg/min)"
    FROM T_final_norepine 
    LEFT JOIN dobutamine_B3
    ON T_final_norepine.subject_id = dobutamine_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------
                                                    /*Phenyphrine*/
----------------------------------------------------------------------------------------------------------------------
/*les variables "phenyphrine_J0(mcg/Kg/min)","phenyphrine_J1(mcg/Kg/min)","phenyphrine_J2(mcg/Kg/min)",
"phenyphrine_J3(mcg/Kg/min)" renseignants sur les quantités de phenyphrine administrées au patient
à J0, J1,J2 et J3 sont construites sur le même preincipe que les variables de la section
d'epinephrine. Dans un premier temps, on récupère toutes les mesures de phenyphrine dans la vue 'V_mesurephenyphrine'*
Ensuite, on ramene le taux d'administration(mcg/Kg/min) en mcg/Kg en multipliant par la durée d'administation
puis en divisant la durée totale d'administation du dopimine lorsqu'on est à J0 ou en en divisant par (24*60) 
lorsqu'on est à J1, J2 et J3.*/

CREATE OR REPLACE VIEW V_mesurephenylephrine AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =221749
;

CREATE OR REPLACE VIEW V_phenylephr AS
    SELECT V_mesurephenylephrine.*,
    (EXTRACT(epoch FROM V_mesurephenylephrine.endtime - V_mesurephenylephrine.starttime))/60 AS duree_minutes
    FROM V_mesurephenylephrine
;

CREATE OR REPLACE VIEW V_phenylephrine AS
    SELECT V_phenylephr.*,
    (V_phenylephr.duree_minutes*V_phenylephr.rate) AS mesure_mcg_kg
    FROM V_phenylephr
;

CREATE OR REPLACE VIEW V_phenylephrine_final AS
    SELECT sum(V_phenylephrine.mesure_mcg_kg) sum_phenylephrine,
            sum(duree_minutes) duree_patientjour,
            V_phenylephrine.subject_id,
            date(V_phenylephrine.starttime) starttime
    FROM V_phenylephrine
    GROUP BY V_phenylephrine.subject_id, date(V_phenylephrine.starttime)
;

CREATE OR REPLACE VIEW phenylephrine_0 as select T_final_lactate.*
,V_phenylephrine_final.sum_phenylephrine/(V_phenylephrine_final.duree_patientjour) AS "phenylephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_phenylephrine_final
    ON V_phenylephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_phenylephrine_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW phenylephrine_1 AS 
SELECT T_final_lactate.*
,V_phenylephrine_final.sum_phenylephrine/(24*60) AS "phenylephrine_J1(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_phenylephrine_final
    ON V_phenylephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_phenylephrine_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW phenylephrine_2 AS 
SELECT T_final_lactate.*
,V_phenylephrine_final.sum_phenylephrine/(24*60) AS "phenylephrine_J2(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_phenylephrine_final
    ON V_phenylephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_phenylephrine_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW phenylephrine_3 AS 
SELECT T_final_lactate.*
,V_phenylephrine_final.sum_phenylephrine/(24*60) AS "phenylephrine_J3(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN V_phenylephrine_final
    ON V_phenylephrine_final.subject_id = T_final_lactate.subject_id
    WHERE V_phenylephrine_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW phenylephrine_B0 AS 
    SELECT T_final_lactate.*, phenylephrine_0."phenylephrine_J0(mcg/Kg/min)"
    FROM T_final_lactate
    LEFT JOIN phenylephrine_0
    ON phenylephrine_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW phenylephrine_B1 AS 
    SELECT phenylephrine_B0.*, phenylephrine_1."phenylephrine_J1(mcg/Kg/min)"
    FROM phenylephrine_B0
    LEFT JOIN phenylephrine_1
    ON phenylephrine_1.subject_id = phenylephrine_B0.subject_id
;

CREATE OR REPLACE VIEW phenylephrine_B2 AS 
    SELECT phenylephrine_B1.*, phenylephrine_2."phenylephrine_J2(mcg/Kg/min)"
    FROM phenylephrine_B1
    LEFT JOIN phenylephrine_2
    ON phenylephrine_2.subject_id = phenylephrine_B1.subject_id
;

CREATE OR REPLACE VIEW phenylephrine_B3 AS 
    SELECT phenylephrine_B2.*, phenylephrine_3."phenylephrine_J3(mcg/Kg/min)"
    FROM phenylephrine_B2
    LEFT JOIN phenylephrine_3
    ON phenylephrine_3.subject_id = phenylephrine_B2.subject_id
;

CREATE TABLE T_final_phenyphrine AS 
    SELECT T_final_dobutamine.*
    ,phenylephrine_B3."phenylephrine_J0(mcg/Kg/min)"
    ,phenylephrine_B3."phenylephrine_J1(mcg/Kg/min)"
    ,phenylephrine_B3."phenylephrine_J2(mcg/Kg/min)"
    ,phenylephrine_B3."phenylephrine_J3(mcg/Kg/min)"
    FROM T_final_dobutamine 
    LEFT JOIN phenylephrine_B3
    ON T_final_dobutamine.subject_id = phenylephrine_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------
                                                    /*Catecholamine*/
----------------------------------------------------------------------------------------------------------------------
/* Les catécholamines sont constituées d'epinephrine,de dopamine, de norepinephrine, de dobutamine et de phenylephrine. L'un des
critères d'inclusion est la variable 'necessité de catecholamine'. N'existant pas dans la base de données, nous avons créé un substitut
qui se base sur les variables 'epinephrine_J0(mcg/Kg/min)',"epinephrine_J1(mcg/Kg/min)","dopamine_J0(mcg/Kg/min)","dopamine_J1(mcg/Kg/min)"
"norepinephrine_J0(mcg/Kg/min)","norepinephrine_J1(mcg/Kg/min)","dobutamine_J0(mcg/Kg/min)","dobutamine_J1(mcg/Kg/min)",
."phenylephrine_J0(mcg/Kg/min)","phenylephrine_J1(mcg/Kg/min)". Le substitut nommé 'catecholamine' prend la valeur 1 si l'une de ces 
variables est non null(autrement dit il existe au moins une valeur) à J0 et J1 et la valeur 0 si toutes ces variables sont nulles à J0 
et J1*/

CREATE TABLE T_base_catecholamine AS 
    SELECT T_final_phenyphrine.*,
        (CASE
            WHEN
            (T_final_phenyphrine."epinephrine_J0(mcg/Kg/min)" is null AND
            T_final_phenyphrine."epinephrine_J1(mcg/Kg/min)" is null AND
            
            T_final_phenyphrine."dopamine_J0(mcg/Kg/min)" is null AND
            T_final_phenyphrine."dopamine_J1(mcg/Kg/min)" is null AND

            T_final_phenyphrine."norepinephrine_J0(mcg/Kg/min)" is null AND
            T_final_phenyphrine."norepinephrine_J1(mcg/Kg/min)" is null AND
            
            T_final_phenyphrine."dobutamine_J0(mcg/Kg/min)" is null AND
            T_final_phenyphrine."dobutamine_J1(mcg/Kg/min)" is null AND

            T_final_phenyphrine."phenylephrine_J0(mcg/Kg/min)" is null AND
            T_final_phenyphrine."phenylephrine_J1(mcg/Kg/min)" is null  ) THEN '0'
 
            ELSE '1'
            END
        ) AS catecholamine

FROM T_final_phenyphrine
;

/*Pour le reste de l'analyse, nous ne considérons que les individus ayant une valeur de 'catécholamine' égale à 1. Autrement dit, ceux 
qui ont une nécéssité de catécholamine*/
CREATE TABLE T_base_utile AS
    SELECT * 
    FROM T_base_catecholamine
    WHERE T_base_catecholamine.catecholamine ='1'
;	

----------------------------------------------------------------------------------------------------------------------
                                                    /*Mortalite*/
----------------------------------------------------------------------------------------------------------------------
/*Comme objectif du projet, nous voulons etudier le lien entre la mortalité et les fuites capillaires. Pour cela, nous effectuons
une jointure entre la table 'T_base_utile' et la table 'patient' dans le but de récupérer la variable 'dod' qui informe sur la date 
de decès des patients jusqu'au an après leur sortie de l'hopital. Cette jointure permet de récuperer la date de deces des patients
si elle existe des patients qui étaient vivants à leur sortie de l'hopital et qui sont morts durant les 1 ans qui ont suivi leur sortie.*/
CREATE OR REPLACE VIEW V_morta_dod AS
    SELECT bf.*,pt.dod
    FROM T_base_utile bf
    INNER JOIN mimiciv_hosp.patients pt
    ON bf.subject_id=pt.subject_id 
;

/*Pour les individus qui sont décédés pendant leur séjour à l'hopital, leur date de décès se trouve dans la variable 'deathtime' de 
la table 'admissions'. Aussi dans cette table, se trouve la variable 'hospital_expire_flag' qui prend la valeur 1 si l'individu est 
décédé à l'hopital et 0 sinon. Ainsi, la jointure suivante permettra de récupérer les variables 'deathtime' et 'hospital_expire_flag'.*/
CREATE OR REPLACE VIEW V_mortali_admission AS
    SELECT bf.*,ad.hospital_expire_flag,ad.deathtime
    FROM V_morta_dod bf
    INNER JOIN mimiciv_hosp.admissions ad
    ON ad.subject_id=bf.subject_id and ad.hadm_id=bf.hadm_id
;

/*Création de la variable 'deces_date' qui contient la date de deces dans la vue 'V_mortalite'. Donc, lorsque 'hospital_expire_flag'est 
égale à 1, la variable 'deces_date' prendra la valeur de deathtime et si 'hospital_expire_flag'est égale à 0, la variable 'deces_date' 
sera égale à la variable 'dod'.En plus de cette variable, la vue 'V_mortalite' contient toutes les variables de la table 'T_base_utile'
et tous ces individus.*/
CREATE OR REPLACE VIEW V_mortalite AS
    SELECT V_mortali_admission.* 
    ,(CASE
		WHEN(V_mortali_admission.hospital_expire_flag='1') then date(V_mortali_admission.deathtime)
		ELSE  V_mortali_admission.dod 
	END) AS deces_date 
	FROM V_mortali_admission
;

/*Création dans la table 'T_mortalite_final' les variables indicatrices de décès. En effet, la variable 'indicatrice_deces_J0' 
prend la valeur '1' si l'individu est décédé à J0 et 0 sinon. 'indicatrice_deces_J1' quand à elle prend la valeur '1' si l'individu 
est décédé entre J0 et J1 et 0 sinon. C'est sur le meme principe que sont créé les variables 'indicatrice_deces_J2',
'indicatrice_deces_J3','indicatrice_deces_J7' et 'indicatrice_deces_J30'.

*/
CREATE TABLE T_mortalite_final AS
    SELECT V_mortalite.*
    ,(CASE
		WHEN(V_mortalite.J0=V_mortalite.deces_date) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J0
    ,(CASE
		WHEN(V_mortalite.deces_date<=date(V_mortalite.J0 + INTERVAL '1 DAY')) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J1
    ,(CASE
		WHEN(V_mortalite.deces_date<=date(V_mortalite.J0 + INTERVAL '2 DAY')) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J2
    ,(CASE
		WHEN(V_mortalite.deces_date<=date(V_mortalite.J0 + INTERVAL '3 DAY')) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J3
    ,(CASE
		WHEN(V_mortalite.deces_date<=date(V_mortalite.J0 + INTERVAL '7 DAY')) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J7
    ,(CASE
		WHEN(V_mortalite.deces_date<=date(V_mortalite.J0 + INTERVAL '30 DAY')) then '1'
	    ELSE '0'
	END) AS indicatrice_deces_J30
	FROM V_mortalite
;
----jointure de V_mortalite_final avec les patients de travail

/*Création de la table 'T_basefinal_utile' qui est une jointure entre la table 'T_base_utile' et les variables indicatrices
de decès créées plus haut dans la table 'T_mortalite_final' .*/

CREATE TABLE T_basefinal_utile AS 
    SELECT T_base_utile.*
    ,T_mortalite_final.deces_date
	,T_mortalite_final.indicatrice_deces_J0
	,T_mortalite_final.indicatrice_deces_J1
	,T_mortalite_final.indicatrice_deces_J2
	,T_mortalite_final.indicatrice_deces_J3
	,T_mortalite_final.indicatrice_deces_J14
	,T_mortalite_final.indicatrice_deces_J30
    FROM T_base_utile
    LEFT JOIN T_mortalite_final
    ON T_base_utile.subject_id = T_mortalite_final.subject_id
;


/*Dans cette section, nous cherchons à créer une variable indicatrice de glycémie qui indique si la glycémie est anormale ou pas.
Ainsi, cette indicatrice prendra la valeur 1 si le glucose est soit inférieur à 0.7 ou supérieure à 1.8 .
La variable renseignant sur la quantité glucose se trouvent dans la table 'labevents' et également dans la table 'chartevents'.
Dans un premier temps, nous créons les variables glycemie_max et glycemie_min qui contiennent respectivement la valeur maximale et minimale 
de glucose provenant de la table 'labevents' pour tous les jours. 
Ensuite, nous créeons les variables glycemie_chart1_max et glycemie_chart1_min qui representent respectivement les quantités
maximale et minimale de glucose (issue de la table chartevents avec l'itemid=226537(glucose whole blood)) pour tous les jours. 
Puis, nous allons créer les variables glycemie_serum_max et glycemie_serum_min qui representent respectivement les quantités
maximale et minimale de glucose (issue de la table chartevents avec l'itemid=220621(glucose(serum))) pour tous les jours.
Et ce sont toutes ces variables que nous considérerons pour la création de nos indicatrices de glycémie. */

--------------------------------------------------------------------------------------------------------------------------
                                    /*			Glucoce dans labevents          */
--------------------------------------------------------------------------------------------------------------------------
--Nous créons une vue 'V_mesureglycemie_max' qui contient toutes les mesures de glucose provenant de la table 'labevents'

CREATE OR REPLACE VIEW V_mesureglycemie_max AS
    SELECT *
    FROM mimiciv_hosp.labevents lab
    WHERE lab.itemid IN (SELECT itemid 
                        FROM mimiciv_hosp.d_labitems 
                        WHERE LOWER(label) LIKE '%glucose%' and fluid='Blood')
;

--Ensuite, nous crééons la vue 'V_glycemie' qui se base sur la vue précédente 'V_mesureglycemie_max' mais contient la valeur maximale
--et minimale de glucose par patient dans chaque journée. La division par 100 est faite pour ramener l'unité du glucose à g/L.
--En effet, dans la table 'labevents', les valeurs de glucose renseignées sont en g/dL.
 
CREATE OR REPLACE VIEW V_glycemie AS
    SELECT 
	(max(V_mesureglycemie_max.valuenum)/100) AS value_max
    ,(min(V_mesureglycemie_max.valuenum)/100) AS value_min
    ,V_mesureglycemie_max.subject_id,date(V_mesureglycemie_max.charttime) charttime
    FROM V_mesureglycemie_max
    GROUP BY V_mesureglycemie_max.subject_id, date(V_mesureglycemie_max.charttime)
;

--Ensuite, nous effectuons une jointure entre la table 'T_final_lactate' et la vue 'V_glycemie' lorque la date de prelevement equivaut au
-- jour où le patient a eu son arrêt cardiaque pour créer la vue 'glycemie_max_0'.

CREATE OR REPLACE VIEW glycemie_max_0 AS 
SELECT T_final_lactate.*
    ,V_glycemie.value_max "glycemie_max_J0(g/L)"
    ,V_glycemie.value_min "glycemie_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie
    ON V_glycemie.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie.charttime = T_final_lactate.J0
;

-- De même, pour créer la vue 'glycemie_max_1', nous effectuons une jointure entre la table 'T_final_lactate' et la vue 'V_glycemie' lorque la 
-- date de prelevement equivaut au jour suivant l'arrêt cardiaque du patient dans le but de récupérer dans les variables "glycemie_max_J1(g/L)"
-- et "glycemie_min_J1(g/L)" les valeurs maximales et minimales de glucose des patients à J1.

CREATE OR REPLACE VIEW glycemie_max_1 
AS SELECT T_final_lactate.*
    ,V_glycemie.value_max "glycemie_max_J1(g/L)"
    ,V_glycemie.value_min "glycemie_min_J1(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie
    ON V_glycemie.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie.charttime = T_final_lactate.J1
;

-- De même, pour créer la vue 'glycemie_max_2', nous effectuons une jointure entre la table 'T_final_lactate' et la vue 'V_glycemie' lorque la 
-- date de prelevement coincide avec le J2 du patient dans le but de récupérer dans les variables "glycemie_max_J2(g/L)"
-- et "glycemie_min_J2(g/L)" les valeurs maximales et minimales de glucose des patients à J2.

CREATE OR REPLACE VIEW glycemie_max_2 AS 
    SELECT T_final_lactate.*
    ,V_glycemie.value_max "glycemie_max_J2(g/L)"
    ,V_glycemie.value_min "glycemie_min_J2(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie
    ON V_glycemie.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie.charttime = T_final_lactate.J2
;

-- De même, pour créer la vue 'glycemie_max_3', nous effectuons une jointure entre la table 'T_final_lactate' et la vue 'V_glycemie' lorque la 
-- date de prelevement coincide avec le J3 du patient dans le but de récupérer dans les variables "glycemie_max_J3(g/L)" et
-- "glycemie_min_J3(g/L)", les valeurs maximales et minimales de glucose des patients à J3.
CREATE OR REPLACE VIEW glycemie_max_3 AS 
    SELECT T_final_lactate.*
    ,V_glycemie.value_max "glycemie_max_J3(g/L)"
    ,V_glycemie.value_min "glycemie_min_J3(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie
    ON V_glycemie.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie.charttime = T_final_lactate.J3
;

-------------------Jointures
/*Ensuite,nous effectuons la jointure entre 'T_final_lactate' et 'glycemie_max_0' dans le but de finaliser les variables 
"glycemie_max_J0(g/L)" et "glycemie_min_J0(g/L)". En effet, les individus à qui aucune mesure de glucose n'a été faite à J0(les individus
qui sont dans la table 'T_final_lactate' sans être dans la vue 'glycemie_max_0') auront une valeur 'null' et 
les individus qui sont à la fois dans la vue 'glycemie_max_0' et dans la table 'T_final_lactate' auront les valeurs de 
"glycemie_max_J0(g/L)" et de "glycemie_min_J0(g/L)" qu'ils avaient dans la vue 'glycemie_max_0'*/

CREATE OR REPLACE VIEW glycemie_max_B0 AS 
    SELECT T_final_lactate.*
    , glycemie_max_0."glycemie_max_J0(g/L)"
    , glycemie_max_0."glycemie_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN glycemie_max_0
    ON glycemie_max_0.subject_id = T_final_lactate.subject_id
;

/*Sur le même principe, on fait une jointure entre les 'glycemie_max_B0' et 'glycemie_max_1'. En effet, la vue 'glycemie_max_B0' n'est 
que l'ajout des variables "glycemie_max_J0(g/L)" et de "glycemie_min_J0(g/L)" à la table 'T_final_lactate'. Cette jointure est faite 
dans le but d'ajouter les variables "glycemie_max_J1(g/L)" et "glycemie_min_J1(g/L)" aux variables de la vue 'glycemie_max_B0'. 
Et tout comme pour la vue 'glycemie_max_B0', les variables "glycemie_max_J1(g/L)" et "glycemie_min_J1(g/L)" prendront la valeur 'NULL' 
si aucune mesure de glucose n'a été éffectuée à J1 pour le patient.*/

CREATE OR REPLACE VIEW glycemie_max_B1 AS
    SELECT glycemie_max_B0.*
    , glycemie_max_1."glycemie_max_J1(g/L)"
    , glycemie_max_1."glycemie_min_J1(g/L)"
    FROM glycemie_max_B0
    LEFT JOIN glycemie_max_1
    ON glycemie_max_1.subject_id = glycemie_max_B0.subject_id
;

/*Sur le même principe, on fait une jointure entre les 'glycemie_max_B1' et 'glycemie_max_2'.  Cette jointure est faite 
dans le but d'ajouter les variables "glycemie_max_J2(g/L)" et "glycemie_min_J2(g/L)" aux variables de la vue 'glycemie_max_B1'. 
Et tout comme pour la vue 'glycemie_max_B0', les variables "glycemie_max_J2(g/L)" et "glycemie_min_J2(g/L)" prendront la valeur 'NULL' 
si aucune mesure de glucose n'a été éffectuée à J2 pour le patient. Cette vue contient ,donc, pour tous les individus ayant un lactate
supérieur à 2 , les variables de la table 'T_finale_lactate' et les variables "glycemie_max_J0(g/L)", "glycemie_min_J0(g/L)" ,
"glycemie_max_J1(g/L)" et "glycemie_min_J1(g/L)","glycemie_max_J2(g/L)" et "glycemie_min_J2(g/L)". */

CREATE OR REPLACE VIEW glycemie_max_B2 AS
    SELECT glycemie_max_B1.*
    , glycemie_max_2."glycemie_max_J2(g/L)"
    , glycemie_max_2."glycemie_min_J2(g/L)"
    FROM glycemie_max_B1
    LEFT JOIN glycemie_max_2
    ON glycemie_max_2.subject_id = glycemie_max_B1.subject_id
;

/*De même, nous créons la vue 'glycemie_max_B3' pour contenir en plus des variables de la table 'T_finale_lactate',
les variables "glycemie_max_J0(g/L)", "glycemie_min_J0(g/L)" ,"glycemie_max_J1(g/L)", "glycemie_min_J1(g/L)","glycemie_max_J2(g/L)", 
"glycemie_min_J2(g/L)","glycemie_max_J3(g/L)" et "glycemie_min_J3(g/L)". Notons que les variables "glycemie_max_J3(g/L)" et 
"glycemie_min_J3(g/L)" prendront la valeur 'NULL' si aucune mesure de glucose n'a été éffectuée à J3 pour le patient.*/
CREATE OR REPLACE VIEW glycemie_max_B3 AS
    SELECT glycemie_max_B2.*
    , glycemie_max_3."glycemie_max_J3(g/L)"
    , glycemie_max_3."glycemie_min_J3(g/L)"
    FROM glycemie_max_B2
    LEFT JOIN glycemie_max_3
    ON glycemie_max_3.subject_id = glycemie_max_B2.subject_id
;

/*Ayant dans 'glycemie_max_B3', toutes les variables de glucose pour J0,J1,J2 et J3. Nous éffectuons une jointure entre la table
'T_basefinal_utile' et la vue 'glycemie_max_B3' afin de créer la table 'T_final_glycemie_glycemie'. En effet, la table 
'T_basefinal_utile' contient les indicatrices de décès et les variables renseignant sur les quantités de catécholamines.*/ 
CREATE TABLE T_final_glycemie_glycemie AS 
    SELECT T_basefinal_utile.*
	,glycemie_max_B3."glycemie_max_J3(g/L)"
	,glycemie_max_B3."glycemie_max_J2(g/L)"
	,glycemie_max_B3."glycemie_max_J1(g/L)"
	,glycemie_max_B3."glycemie_max_J0(g/L)"
	,glycemie_max_B3."glycemie_min_J3(g/L)"
	,glycemie_max_B3."glycemie_min_J2(g/L)"
	,glycemie_max_B3."glycemie_min_J1(g/L)"
	,glycemie_max_B3."glycemie_min_J0(g/L)"
    FROM T_basefinal_utile
    LEFT JOIN glycemie_max_B3
    ON T_basefinal_utile.subject_id = glycemie_max_B3.subject_id
;

/*Note: la table 'T_final_glycemie_glycemie' contient pour tous les individus ayant une mesure de lactate supérieur à 2 et 
ayant un besoin de catécholamine, les variables suivantes : 'subject_id';'hadm_id';'datedebut';'J0';'J1';'J2';'J3';'age';'gender';
'anchor_age';'anchor_year';'anchor_group_year'; les valeurs moyennes de ph à J0,J1,J2,J3; les températures maximales de températures
à J0,J1,J2,J3; les indicatrices d'hyperthermie à à J0,J1,J2,J3; les valeurs des catécholamines (epinephrine,dobutamine,dopamine,
norepinephrine,phenylephrine); la date de decès; les indicatrices de decès à J0,J1,J2,J3,J14,J30 ; les valeurs maximales et minimales 
de glucose de J0,J1,J2,J3 issues de la table 'labevents' .*/

----------------------------------------------------------------------------------------------------------------------------------
					                                    /*Glucose chartevents*/
----------------------------------------------------------------------------------------------------------------------------------
/*De la même manière qu'ont été construites les variables "glycemie_max_J3(g/L)","glycemie_max_J2(g/L)","glycemie_max_J1(g/L)",
"glycemie_max_J0(g/L)","glycemie_min_J3(g/L)","glycemie_min_J2(g/L)","glycemie_min_J1(g/L)","glycemie_min_J0(g/L)"; nous construisons
les variables "glycemie_chart1_max_J3(g/L)","glycemie_chart1_max_J2(g/L)","glycemie_chart1_max_J1(g/L)","glycemie_chart1_max_J0(g/L)",
"glycemie_chart1_min_J3(g/L)","glycemie_chart1_min_J2(g/L)","glycemie_chart1_min_J1(g/L)","glycemie_chart1_min_J0(g/L)". La seule  
différence est que les valeurs de glucose proviennent de la table 'chartevents' et correspondent à l'itemid=226537(glucose(whole blood)).*/
CREATE OR REPLACE VIEW V_mesureglycemie_chart1_max AS
    SELECT *
    FROM mimiciv_icu.chartevents lab
    WHERE lab.itemid = 226537 
;

CREATE OR REPLACE VIEW V_glycemie_chart1 AS
    SELECT (max(V_mesureglycemie_chart1_max.valuenum)/100) AS value_max
    , (min(V_mesureglycemie_chart1_max.valuenum)/100) AS value_min
    ,V_mesureglycemie_chart1_max.subject_id,date(V_mesureglycemie_chart1_max.charttime) charttime
    FROM V_mesureglycemie_chart1_max
    GROUP BY V_mesureglycemie_chart1_max.subject_id, date(V_mesureglycemie_chart1_max.charttime)
;

CREATE OR REPLACE VIEW glycemie_chart1_max_0 AS 
SELECT T_final_lactate.*
    ,V_glycemie_chart1.value_max "glycemie_chart1_max_J0(g/L)"
    ,V_glycemie_chart1.value_min "glycemie_chart1_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_chart1
    ON V_glycemie_chart1.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_chart1.charttime = T_final_lactate.J0
;

select*from glycemie_chart1_max_0;

CREATE OR REPLACE VIEW glycemie_chart1_max_1 AS 
SELECT T_final_lactate.*
    ,V_glycemie_chart1.value_max "glycemie_chart1_max_J1(g/L)"
    ,V_glycemie_chart1.value_min "glycemie_chart1_min_J1(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_chart1
    ON V_glycemie_chart1.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_chart1.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW glycemie_chart1_max_2 AS 
    SELECT T_final_lactate.*
    ,V_glycemie_chart1.value_max "glycemie_chart1_max_J2(g/L)"
    ,V_glycemie_chart1.value_min "glycemie_chart1_min_J2(g/L)"
        FROM T_final_lactate
        LEFT JOIN V_glycemie_chart1
        ON V_glycemie_chart1.subject_id = T_final_lactate.subject_id
        WHERE V_glycemie_chart1.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW glycemie_chart1_max_3 AS 
SELECT T_final_lactate.*
,V_glycemie_chart1.value_max "glycemie_chart1_max_J3(g/L)"
,V_glycemie_chart1.value_min "glycemie_chart1_min_J3(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_chart1
    ON V_glycemie_chart1.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_chart1.charttime = T_final_lactate.J3
;

------------------Jointures
CREATE OR REPLACE VIEW glycemie_chart1_max_B0 AS 
    SELECT T_final_lactate.*
    , glycemie_chart1_max_0."glycemie_chart1_max_J0(g/L)"
    , glycemie_chart1_max_0."glycemie_chart1_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN glycemie_chart1_max_0
    ON glycemie_chart1_max_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW glycemie_chart1_max_B1 AS
    SELECT glycemie_chart1_max_B0.*
    , glycemie_chart1_max_1."glycemie_chart1_max_J1(g/L)"
    , glycemie_chart1_max_1."glycemie_chart1_min_J1(g/L)"
    FROM glycemie_chart1_max_B0
    LEFT JOIN glycemie_chart1_max_1
    ON glycemie_chart1_max_1.subject_id = glycemie_chart1_max_B0.subject_id
;

CREATE OR REPLACE VIEW glycemie_chart1_max_B2 AS
    SELECT glycemie_chart1_max_B1.*
    , glycemie_chart1_max_2."glycemie_chart1_max_J2(g/L)"
    , glycemie_chart1_max_2."glycemie_chart1_min_J2(g/L)"
    FROM glycemie_chart1_max_B1
    LEFT JOIN glycemie_chart1_max_2
    ON glycemie_chart1_max_2.subject_id = glycemie_chart1_max_B1.subject_id
;

CREATE OR REPLACE VIEW glycemie_chart1_max_B3 AS
    SELECT glycemie_chart1_max_B2.*
    , glycemie_chart1_max_3."glycemie_chart1_max_J3(g/L)"
    , glycemie_chart1_max_3."glycemie_chart1_min_J3(g/L)"
    FROM glycemie_chart1_max_B2
    LEFT JOIN glycemie_chart1_max_3
    ON glycemie_chart1_max_3.subject_id = glycemie_chart1_max_B2.subject_id
;


CREATE TABLE T_final_glycemie_chart1 AS 
    SELECT T_final_glycemie_glycemie.*
	,glycemie_chart1_max_B3."glycemie_chart1_max_J3(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_max_J2(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_max_J1(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_max_J0(g/L)"
    ,glycemie_chart1_max_B3."glycemie_chart1_min_J3(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_min_J2(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_min_J1(g/L)"
	,glycemie_chart1_max_B3."glycemie_chart1_min_J0(g/L)"
    FROM T_final_glycemie_glycemie
    LEFT JOIN glycemie_chart1_max_B3
    ON T_final_glycemie_glycemie.subject_id = glycemie_chart1_max_B3.subject_id
;
------------------------------------------------------------------------------------------------------------
                                        /*Glucose(serum)*/
-----------------------------------------------------------------------------------------------------------
/*De la même manière qu'on été construites les variables "glycemie_max_J3(g/L)","glycemie_max_J2(g/L)","glycemie_max_J1(g/L)",
"glycemie_max_J0(g/L)","glycemie_min_J3(g/L)","glycemie_min_J2(g/L)","glycemie_min_J1(g/L)","glycemie_min_J0(g/L)",
"glycemie_chart1_max_J3(g/L)","glycemie_chart1_max_J2(g/L)","glycemie_chart1_max_J1(g/L)","glycemie_chart1_max_J0(g/L)",
"glycemie_chart1_min_J3(g/L)","glycemie_chart1_min_J2(g/L)","glycemie_chart1_min_J1(g/L)","glycemie_chart1_min_J0(g/L)"; 
nous construisons les variables "glycemie_serum_max_J3(g/L)","glycemie_serum_max_J2(g/L)","glycemie_serum_max_J1(g/L)",
"glycemie_serum_max_J0(g/L)","glycemie_serum_min_J3(g/L)","glycemie_serum_min_J2(g/L)","glycemie_serum_min_J1(g/L)",
"glycemie_serum_min_J0(g/L)". La seule différence est que les valeurs de glucose proviennent de la table 'chartevents' 
et correspondent à l'itemid=220621(glucose(serum)).*/

CREATE OR REPLACE VIEW V_mesureglycemie_serum_max AS
    SELECT *
    FROM mimiciv_icu.chartevents lab
    WHERE lab.itemid = 220621 
;

CREATE OR REPLACE VIEW V_glycemie_serum AS
    SELECT (max(V_mesureglycemie_serum_max.valuenum)/100) AS value_max
    , (min(V_mesureglycemie_serum_max.valuenum)/100) AS value_min
    ,V_mesureglycemie_serum_max.subject_id,date(V_mesureglycemie_serum_max.charttime) charttime
    FROM V_mesureglycemie_serum_max
    GROUP BY V_mesureglycemie_serum_max.subject_id, date(V_mesureglycemie_serum_max.charttime)
;

CREATE OR REPLACE VIEW glycemie_serum_max_0 AS 
SELECT T_final_lactate.*
    ,V_glycemie_serum.value_max "glycemie_serum_max_J0(g/L)"
    ,V_glycemie_serum.value_min "glycemie_serum_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_serum
    ON V_glycemie_serum.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_serum.charttime = T_final_lactate.J0
;

select*from glycemie_serum_max_0;

CREATE OR REPLACE VIEW glycemie_serum_max_1 AS 
SELECT T_final_lactate.*
    ,V_glycemie_serum.value_max "glycemie_serum_max_J1(g/L)"
    ,V_glycemie_serum.value_min "glycemie_serum_min_J1(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_serum
    ON V_glycemie_serum.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_serum.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW glycemie_serum_max_2 AS 
    SELECT T_final_lactate.*
    ,V_glycemie_serum.value_max "glycemie_serum_max_J2(g/L)"
    ,V_glycemie_serum.value_min "glycemie_serum_min_J2(g/L)"
        FROM T_final_lactate
        LEFT JOIN V_glycemie_serum
        ON V_glycemie_serum.subject_id = T_final_lactate.subject_id
        WHERE V_glycemie_serum.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW glycemie_serum_max_3 AS 
SELECT T_final_lactate.*
,V_glycemie_serum.value_max "glycemie_serum_max_J3(g/L)"
,V_glycemie_serum.value_min "glycemie_serum_min_J3(g/L)"
    FROM T_final_lactate
    LEFT JOIN V_glycemie_serum
    ON V_glycemie_serum.subject_id = T_final_lactate.subject_id
    WHERE V_glycemie_serum.charttime = T_final_lactate.J3
;

------------------Jointures
CREATE OR REPLACE VIEW glycemie_serum_max_B0 AS 
    SELECT T_final_lactate.*
    , glycemie_serum_max_0."glycemie_serum_max_J0(g/L)"
    , glycemie_serum_max_0."glycemie_serum_min_J0(g/L)"
    FROM T_final_lactate
    LEFT JOIN glycemie_serum_max_0
    ON glycemie_serum_max_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW glycemie_serum_max_B1 AS
    SELECT glycemie_serum_max_B0.*
    , glycemie_serum_max_1."glycemie_serum_max_J1(g/L)"
    , glycemie_serum_max_1."glycemie_serum_min_J1(g/L)"
    FROM glycemie_serum_max_B0
    LEFT JOIN glycemie_serum_max_1
    ON glycemie_serum_max_1.subject_id = glycemie_serum_max_B0.subject_id
;

CREATE OR REPLACE VIEW glycemie_serum_max_B2 AS
    SELECT glycemie_serum_max_B1.*
    , glycemie_serum_max_2."glycemie_serum_max_J2(g/L)"
    , glycemie_serum_max_2."glycemie_serum_min_J2(g/L)"
    FROM glycemie_serum_max_B1
    LEFT JOIN glycemie_serum_max_2
    ON glycemie_serum_max_2.subject_id = glycemie_serum_max_B1.subject_id
;

CREATE OR REPLACE VIEW glycemie_serum_max_B3 AS
    SELECT glycemie_serum_max_B2.*
    , glycemie_serum_max_3."glycemie_serum_max_J3(g/L)"
    , glycemie_serum_max_3."glycemie_serum_min_J3(g/L)"
    FROM glycemie_serum_max_B2
    LEFT JOIN glycemie_serum_max_3
    ON glycemie_serum_max_3.subject_id = glycemie_serum_max_B2.subject_id
;

CREATE TABLE T_final_glycemie_serum AS 
    SELECT T_final_glycemie_chart1.*
	,glycemie_serum_max_B3."glycemie_serum_max_J3(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_max_J2(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_max_J1(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_max_J0(g/L)"
    ,glycemie_serum_max_B3."glycemie_serum_min_J3(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_min_J2(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_min_J1(g/L)"
	,glycemie_serum_max_B3."glycemie_serum_min_J0(g/L)"
    FROM T_final_glycemie_chart1
    LEFT JOIN glycemie_serum_max_B3
    ON T_final_glycemie_chart1.subject_id = glycemie_serum_max_B3.subject_id
;    

------------------------------------------------------------------------------------------------------------
                /*Indicatrice glycemie (1: <0.7 or >1.8 0: sinon)*/
-----------------------------------------------------------------------------------------------------------
/*Pour créer la variable indicatrice_glycemie pour J0,J1,J2 et J3; nous utilisons la fonction least et greatest. En effet , dans 
un premier temps lorque l'une des variables glycemie_serum_min, glycemie_min, glycemie_chart1_min existe, nous remplacons toutes 
les autres qui sont nulles(n'existent pas) par 100 au moyen de COALESCE et nous comparons la valeur minimale à 0,7. Dans un second temps,
lorsque l'une des variables glycemie_serum_max, glycemie_max et glycemie_chart1_max existe, nous remplacons celles qui n'existent pas
par 0 puis nous comparons la valeur maximale à 1,8. Si la valeur minimale est inférieur à 0,7 ou la valeur maximale est supérieure à 1,8; 
la variable indicatrice_glycemie prend la valeur 1 et 0 sinon. Cependant lorsque toutes ces valeurs sont égale à 'NULL'(n'existe pas),
la variable 'indicatrice_glycemie' prendra la valeur 'NULL'.
*/
CREATE TABLE T_final_glycemie_final AS
SELECT T_final_glycemie_serum.*
    ,(CASE
	WHEN(
            ((T_final_glycemie_serum."glycemie_serum_min_J0(g/L)" is not null 
			  or T_final_glycemie_serum."glycemie_min_J0(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_min_J0(g/L)" is not null)
        and 
            least(COALESCE(T_final_glycemie_serum."glycemie_serum_min_J0(g/L)",100),
				  COALESCE(T_final_glycemie_serum."glycemie_min_J0(g/L)",100),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_min_J0(g/L)",100))<0.7)
        or 
            ((T_final_glycemie_serum."glycemie_serum_max_J0(g/L)" is not null or 
			  T_final_glycemie_serum."glycemie_max_J0(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_max_J0(g/L)" is not null)
        and 
            greatest(COALESCE(T_final_glycemie_serum."glycemie_serum_max_J0(g/L)",0),COALESCE(T_final_glycemie_serum."glycemie_max_J0(g/L)",0),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_max_J0(g/L)",0))>1.8))
    then '1'

    WHEN(
        T_final_glycemie_serum."glycemie_serum_min_J0(g/L)" is null and T_final_glycemie_serum."glycemie_min_J0(g/L)" is null
        and T_final_glycemie_serum."glycemie_chart1_min_J0(g/L)" is null and T_final_glycemie_serum."glycemie_serum_max_J0(g/L)" is null 
        and T_final_glycemie_serum."glycemie_max_J0(g/L)" is null and T_final_glycemie_serum."glycemie_chart1_max_J0(g/L)" is null) 
    then 'Null'

	ELSE '0'

    END) AS indicatrice_glycemie_J0

    ,(CASE
	WHEN(
            ((T_final_glycemie_serum."glycemie_serum_min_J1(g/L)" is not null or T_final_glycemie_serum."glycemie_min_J1(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_min_J1(g/L)" is not null)
        and 
            least(COALESCE(T_final_glycemie_serum."glycemie_serum_min_J1(g/L)",100),
				  COALESCE(T_final_glycemie_serum."glycemie_min_J1(g/L)",100),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_min_J1(g/L)",100))<0.7)
        or 
            ((T_final_glycemie_serum."glycemie_serum_max_J1(g/L)" is not null or T_final_glycemie_serum."glycemie_max_J1(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_max_J1(g/L)" is not null)
        and 
            greatest(COALESCE(T_final_glycemie_serum."glycemie_serum_max_J1(g/L)",0),COALESCE(T_final_glycemie_serum."glycemie_max_J1(g/L)",0),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_max_J1(g/L)",0))>1.8))
    then '1'

    WHEN(
        T_final_glycemie_serum."glycemie_serum_min_J1(g/L)" is null and T_final_glycemie_serum."glycemie_min_J1(g/L)" is null
        and T_final_glycemie_serum."glycemie_chart1_min_J1(g/L)" is null and T_final_glycemie_serum."glycemie_serum_max_J1(g/L)" is null 
        and T_final_glycemie_serum."glycemie_max_J1(g/L)" is null and T_final_glycemie_serum."glycemie_chart1_max_J1(g/L)" is null) 
    then 'Null'

	ELSE '0'

    END) AS indicatrice_glycemie_J1

 
    ,(CASE
	WHEN(
            ((T_final_glycemie_serum."glycemie_serum_min_J2(g/L)" is not null or T_final_glycemie_serum."glycemie_min_J2(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_min_J2(g/L)" is not null)
        and 
            least(COALESCE(T_final_glycemie_serum."glycemie_serum_min_J2(g/L)",100),
				  COALESCE(T_final_glycemie_serum."glycemie_min_J2(g/L)",100),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_min_J2(g/L)",100))<0.7) 
        or 
            ((T_final_glycemie_serum."glycemie_serum_max_J2(g/L)" is not null or T_final_glycemie_serum."glycemie_max_J2(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_max_J2(g/L)" is not null)
        and 
            greatest(COALESCE(T_final_glycemie_serum."glycemie_serum_max_J2(g/L)",0),COALESCE(T_final_glycemie_serum."glycemie_max_J2(g/L)",0),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_max_J2(g/L)",0))>1.8))
    then '1'

    WHEN(
        T_final_glycemie_serum."glycemie_serum_min_J2(g/L)" is null and T_final_glycemie_serum."glycemie_min_J2(g/L)" is null
        and T_final_glycemie_serum."glycemie_chart1_min_J2(g/L)" is null and T_final_glycemie_serum."glycemie_serum_max_J2(g/L)" is null 
        and T_final_glycemie_serum."glycemie_max_J2(g/L)" is null and T_final_glycemie_serum."glycemie_chart1_max_J2(g/L)" is null) 
    then 'Null'

	ELSE '0'

    END) AS indicatrice_glycemie_J2
  
    ,(CASE
	WHEN(
            ((T_final_glycemie_serum."glycemie_serum_min_J3(g/L)" is not null or T_final_glycemie_serum."glycemie_min_J3(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_min_J3(g/L)" is not null)
        and 
            least(COALESCE(T_final_glycemie_serum."glycemie_serum_min_J3(g/L)",100),
				  COALESCE(T_final_glycemie_serum."glycemie_min_J3(g/L)",100),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_min_J3(g/L)",100)) <0.7) 
        or 
            ((T_final_glycemie_serum."glycemie_serum_max_J3(g/L)" is not null or T_final_glycemie_serum."glycemie_max_J3(g/L)" is not null 
            or T_final_glycemie_serum."glycemie_chart1_max_J3(g/L)" is not null)
        and 
            greatest(COALESCE(T_final_glycemie_serum."glycemie_serum_max_J3(g/L)",0),COALESCE(T_final_glycemie_serum."glycemie_max_J3(g/L)",0),
            COALESCE(T_final_glycemie_serum."glycemie_chart1_max_J3(g/L)",0))>1.8))
    then '1'

    WHEN(
        T_final_glycemie_serum."glycemie_serum_min_J3(g/L)" is null and T_final_glycemie_serum."glycemie_min_J3(g/L)" is null
        and T_final_glycemie_serum."glycemie_chart1_min_J3(g/L)" is null and T_final_glycemie_serum."glycemie_serum_max_J3(g/L)" is null 
        and T_final_glycemie_serum."glycemie_max_J3(g/L)" is null and T_final_glycemie_serum."glycemie_chart1_max_J3(g/L)" is null) 
    then 'Null'

	ELSE '0'

    END) AS indicatrice_glycemie_J3

FROM T_final_glycemie_serum;


SELECT * FROM T_final_glycemie_final;
----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Albumin*/
----------------------------------------------------------------------------------------------------------------------------------------
-- L'objectif est de récuperer la valeur maximale d'albumin recue par le patient à J0, J1, J2 et J3. Pour cela, dans un premier temps,
-- nous récupérons toutes les mesures d'albumin dans la table 'labevents'
CREATE OR REPLACE VIEW V_mesurealbumin AS
    SELECT *
    FROM mimiciv_hosp.labevents lab
    WHERE lab.itemid = 50862
;

--Ensuite, nous recherchons la valeur maximale par patient et par jour que nous stockons dans la variable 'value_max'.En effet,
-- si on a eu à faire plusieurs prelevements d'albumin à un patient pendant une journée, dans la vue 'V_albumin', chaque prelevement 
--constituera un enregistrement (donc une ligne de la vue). 

CREATE OR REPLACE VIEW V_albumin AS
    SELECT max(V_mesurealbumin.valuenum) value_max,V_mesurealbumin.subject_id,date(V_mesurealbumin.charttime) charttime
    FROM V_mesurealbumin
    GROUP BY V_mesurealbumin.subject_id, date(V_mesurealbumin.charttime)
;

--Une fois qu'on a toutes les valeurs maximales d'albumin par patient et par jour, nous recherchons celles qui correspondent aux valeurs 
--de J0. Ainsi, nous effectuons dans la vue 'albumin_0', une jointure entre la table des individus ayant eu l'arrêt cardiaque et une 
--mesure de lactate supérieure à 2 et la vue 'V_albumin' contenant toutes les mesures maximales d'albumin des patients par jour sous la 
--condition que la date de prelevement corresponde au J0 du patient(WHERE V_albumin.charttime = T_final_lactate.J0)
CREATE OR REPLACE VIEW albumin_0 as
    select T_final_lactate.*,V_albumin.value_max "albumin_J0(g/dL)"
    FROM T_final_lactate
    LEFT JOIN V_albumin
    ON V_albumin.subject_id = T_final_lactate.subject_id
    WHERE V_albumin.charttime = T_final_lactate.J0
;
--De la même manière, nous effectuons la jointure entre 'T_final_lactate' et 'V_albumin' lorque la date de prelevelement correspond
--au J1 du patient. Lorsque la condition est vérifiée, la valeur maximale est récupérée et stockée dans la variable "albumin_J1(g/dL)".
CREATE OR REPLACE VIEW albumin_1 as 
select T_final_lactate.*,V_albumin.value_max "albumin_J1(g/dL)"
    FROM T_final_lactate
    LEFT JOIN V_albumin
    ON V_albumin.subject_id = T_final_lactate.subject_id
    WHERE V_albumin.charttime = T_final_lactate.J1
;

--De même, une jointure est faite entre 'T_final_lactate' et 'V_albumin' lorque la date de prelevelement correspond au J2 du patient. 
--Lorsque la condition est vérifiée, la valeur maximale est récupérée et stockée dans la variable "albumin_J2(g/dL)".
CREATE OR REPLACE VIEW albumin_2 as 
select T_final_lactate.*,V_albumin.value_max "albumin_J2(g/dL)"
    FROM T_final_lactate
    LEFT JOIN V_albumin
    ON V_albumin.subject_id = T_final_lactate.subject_id
    WHERE V_albumin.charttime = T_final_lactate.J2
;

--De même, une jointure est faite entre 'T_final_lactate' et 'V_albumin' lorque la date de prelevelement correspond au J3 du patient. 
--Lorsque la condition est vérifiée, la valeur maximale est récupérée et stockée dans la variable "albumin_J3(g/dL)".
CREATE OR REPLACE VIEW albumin_3 as 
select T_final_lactate.*,V_albumin.value_max "albumin_J3(g/dL)"
    FROM T_final_lactate
    LEFT JOIN V_albumin
    ON V_albumin.subject_id = T_final_lactate.subject_id
    WHERE V_albumin.charttime = T_final_lactate.J3
;

/*Grace aux jointures précedentes, après avoir récupéré les valeurs d'albumin à J0,J1,J2 et J3 lorsqu'elles existent, nous effectuons 
une jointure gauche entre 'T_final_lactate' et 'albumin_0' afin que tous les patients auxquels des mesures d'albumin ont été faites à leur
 J0 aient la valeur maximale stockée dans la variable "albumin_J0(g/dL)" et ceux à qui des mesures d'albumin n'ont pas été faites 
à leur J0 aient une valeur 'NULL' pour la variable "albumin_J0(g/dL)"*/

CREATE OR REPLACE VIEW albumin_B0 AS 
    SELECT T_final_lactate.*, albumin_0."albumin_J0(g/dL)"
    FROM T_final_lactate
    LEFT JOIN albumin_0
    ON albumin_0.subject_id = T_final_lactate.subject_id
;

--La vue 'albumin_B1' est une jointure entre albumin_B0 et albumin_1. Cette jointure permet de récupérer toutes les variables de 'T_final_lactate'
-- la variable "albumin_J0(g/dL)" et la variable "albumin_J1(g/dL)" de la vue 'albumin_1'.Cette jointure permet d'etendre la variable "albumin_J1(g/dL)"
-- à tous les individus de la table 'T_final_lactate'.
CREATE OR REPLACE VIEW albumin_B1 AS
    SELECT albumin_B0.*, albumin_1."albumin_J1(g/dL)"
    FROM albumin_B0
    LEFT JOIN albumin_1
    ON albumin_1.subject_id = albumin_B0.subject_id
;

-- De même, la vue 'albumin_B2' est une jointure entre albumin_B1 et albumin_2. Cette jointure permet de récupérer toutes les variables de 'T_final_lactate'
-- la variable "albumin_J0(g/dL)", la variable "albumin_J1(g/dL)" et la variable "albumin_J2(g/dL)" de la vue 'albumin_2'.Cette jointure 
--permet d'etendre la variable "albumin_J2(g/dL)" à tous les individus de la table 'T_final_lactate'.En effet, la variable "albumin_J2(g/dL)" 
--prendra la valeur 'NULL' si aucune mesure d'albumin n'a été effectuée à J2.

CREATE OR REPLACE VIEW albumin_B2 AS
    SELECT albumin_B1.*, albumin_2."albumin_J2(g/dL)"
    FROM albumin_B1
    LEFT JOIN albumin_2
    ON albumin_2.subject_id = albumin_B1.subject_id
;

-- De même, la vue 'albumin_B3' est une jointure entre albumin_B3 et albumin_3. Cette jointure permet de récupérer toutes les variables de 'T_final_lactate'
-- la variable "albumin_J0(g/dL)", la variable "albumin_J1(g/dL)", la variable "albumin_J2(g/dL)" et la variable "albumin_J3(g/dL)" de la vue 
-- 'albumin_3'. Par ailleurs, la variable "albumin_J3(g/dL)" prendra la valeur 'NULL' si aucune mesure d'albumin n'a été effectuée à J3.

CREATE OR REPLACE VIEW albumin_B3 AS
    SELECT albumin_B2.*, albumin_3."albumin_J3(g/dL)"
    FROM albumin_B2
    LEFT JOIN albumin_3
    ON albumin_3.subject_id = albumin_B2.subject_id
;

-- Pour finir, nous effectuons une jointure entre la table 'T_final_glycemie_final' obtenue àprès la création des indicatrices d'hyperglycémie,
-- et la vue 'albumin_B3' qui contient les variables "albumin_J0(g/dL)","albumin_J1(g/dL)","albumin_J2(g/dL)" et "albumin_J3(g/dL)".
--Cette jointure a pour but d'ajouter ces variables à la table 'T_final_glycemie_final'.
CREATE TABLE V_final_albumin AS 
    SELECT 
    T_final_glycemie_final.* 
    ,albumin_B3."albumin_J0(g/dL)"
    ,albumin_B3."albumin_J1(g/dL)"
    ,albumin_B3."albumin_J2(g/dL)"
    ,albumin_B3."albumin_J3(g/dL)"
    FROM T_final_glycemie_final 
    LEFT JOIN albumin_B3
    ON T_final_glycemie_final.subject_id = albumin_B3.subject_id  
;

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*index cardiaque*/
----------------------------------------------------------------------------------------------------------------------------------------
-- Nous devons selectionner les valeurs minimales et moyennes par jour, les variables  index_cardiac_B0."index_cardiac_min_J0(L/min/m2)"
-- "index_cardiac_max_J0(L/min/m2)" sont crées suivant la même logique que les variables  "glycemie_min_J0(g/L)" et "glycemie_max_J0(g/L)".
-- La seule difference reside dans le fait que pour les variables glycemie, une conversion a été faite(les valeurs
-- etaient divisées par 100) alors que pour les variables de l'index cardiaque, il n'y a pas eu de conversion.
CREATE OR REPLACE VIEW V_mesureindex_cardiac AS
    SELECT*
    FROM mimiciv_icu.chartevents chart
    WHERE chart.itemid= 228368 
;

CREATE OR REPLACE VIEW V_index_cardiac_final AS
    SELECT min(V_mesureindex_cardiac.valuenum) index_cardiac_min,
            avg(V_mesureindex_cardiac.valuenum) index_cardiac_moyen,
            V_mesureindex_cardiac.subject_id,
            date(V_mesureindex_cardiac.charttime) charttime
    FROM V_mesureindex_cardiac
    GROUP BY V_mesureindex_cardiac.subject_id, date(V_mesureindex_cardiac.charttime)
;

CREATE OR REPLACE VIEW index_cardiac_0 AS
SELECT T_final_lactate.*
,T_final_lactate.index_cardiac_min AS "index_cardiac_min_J0(L/min/m2)"
,T_final_lactate.index_cardiac_max AS "index_cardiac_moyen_J0(L/min/m2)"
    FROM T_final_lactate
    LEFT JOIN V_index_cardiac_final
    ON V_index_cardiac_final.subject_id = T_final_lactate.subject_id
    WHERE V_index_cardiac_final.charttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW index_cardiac_B0 AS 
    SELECT T_final_lactate.*, index_cardiac_0."index_cardiac_min_J0(L/min/m2)"
    , index_cardiac_0."index_cardiac_moyen_J0(L/min/m2)"
    FROM T_final_lactate
    LEFT JOIN index_cardiac_0
    ON index_cardiac_0.subject_id = T_final_lactate.subject_id
;

CREATE TABLE T_final_index_cardiac AS 
    SELECT V_final_albumin.*
    ,index_cardiac_B0."index_cardiac_min_J0(L/min/m2)"
    ,index_cardiac_B0."index_cardiac_moyen_J0(L/min/m2)"
    FROM V_final_albumin 
    LEFT JOIN index_cardiac_B0
    ON V_final_albumin.subject_id = index_cardiac_B0.subject_id
;   

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*ultrafiltration*/
----------------------------------------------------------------------------------------------------------------------------------------
--
/*Dans la table 'chartevents',la variable ultrafiltration correspond à l'itemid(226457 : Ultrafiltrate Output) 
donc pour créer cette variable pour les individus ayant eu un arrêt cardiaque et une mesure de lactate supérieure où égale à 2,
dans un premier temps nous récupérons toutes les doses d'ultrafiltration administrées à tous les individus présents dans la base
'mimic'. 
*/
CREATE OR REPLACE VIEW V_mesureultrafiltration AS
    SELECT *
    FROM mimiciv_icu.chartevents char
    WHERE char.itemid = 226457; 

/*Ensuite , nous faisons la somme de toutes les doses récues par patient et par jour.
En effet dans la vue V_mesureultrafiltration précédemment créées une ligne correspond à une quantité d'ultrafiltration 
reçue par un patient pendant un intervalle de temps dans une journée donc si un patient a reçu plusieurs doses d'ultrafiltration 
à différents moments d'une journée, plusieurs lignes seront créées dans cette vue : voilà pourquoi nous faisons la somme de toutes 
les quantités d'ultrafiltrations reçues par le patient durant une journée donnée 
*/
CREATE OR REPLACE VIEW V_ultrafiltration AS
    SELECT sum(V_mesureultrafiltration.valuenum) value_sum
    ,V_mesureultrafiltration.subject_id,date(V_mesureultrafiltration.charttime) charttime
    FROM V_mesureultrafiltration
    GROUP BY V_mesureultrafiltration.subject_id, date(V_mesureultrafiltration.charttime)
;

/*ensuite nous récupérons dans la variable "ultrafiltration_J0(mL)"  la quantité totale d'ultrafiltration donnée chaque patient
lorsque ces dernières ont été administrées le jour où ils ont eu leur arrêt cardiaque 
Voilà pourquoi la vue 'ultrafiltration_0' a été créée comme une jointure des tables 'T_final_lactate' et 
de la vue 'V_ultrafiltration'(contient les quantités totales reçues par jour par les individus )*/
CREATE OR REPLACE VIEW ultrafiltration_0 AS 
SELECT T_final_lactate.*,V_ultrafiltration.value_sum "ultrafiltration_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_ultrafiltration
    ON V_ultrafiltration.subject_id = T_final_lactate.subject_id
    WHERE V_ultrafiltration.charttime = T_final_lactate.J0
;

/*De même pour toutes les quantités d'ultrafiltration reçues par les patients le lendemain de leur arrêt 
cardiaque, nous les récupérons dans la variable "ultrafiltration_J1(mL)" en créant 
la vue  ultrafiltration_1 un qui est une jointure entre la table 'T_final_lactate' et la vue
V_ultrafiltration lorsque le jour d'administration correspond au jour où correspond au J1 du patient */
CREATE OR REPLACE VIEW ultrafiltration_1 AS 
SELECT T_final_lactate.*,V_ultrafiltration.value_sum "ultrafiltration_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_ultrafiltration
    ON V_ultrafiltration.subject_id = T_final_lactate.subject_id
    WHERE V_ultrafiltration.charttime = T_final_lactate.J1
;

--Nous faisons de même pour les variables"ultrafiltration_J2(mL)" et "ultrafiltration_J2(mL)" en créant les 
--vues 'ultrafiltration_2' et 'ultrafiltration_3'
CREATE OR REPLACE VIEW ultrafiltration_2 AS 
SELECT T_final_lactate.*,V_ultrafiltration.value_sum "ultrafiltration_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_ultrafiltration
    ON V_ultrafiltration.subject_id = T_final_lactate.subject_id
    WHERE V_ultrafiltration.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW ultrafiltration_3 AS 
SELECT T_final_lactate.*,V_ultrafiltration.value_sum "ultrafiltration_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_ultrafiltration
    ON V_ultrafiltration.subject_id = T_final_lactate.subject_id
    WHERE V_ultrafiltration.charttime = T_final_lactate.J3
;

/*une fois que nous avons récupéré pour les individus ayant reçu une ultrafiltration le jour de leur arrêt 
cardiaque, nous faisons une jointure entre la table 'T_final_lactate' et la vue 'ultrafiltration_0' dans le 
but d'étendre la variable "ultrafiltration_J0(mL)" à tous les individus présents dans la table des T_final_lactate 
même si ces derniers n'ont reçu aucune dose d'ultrafiltration le jour de leur arrêt cardiaque.Et pour ces derniers 
la valeur de la variable "ultrafiltration_J0(mL)" sera nulle */
CREATE OR REPLACE VIEW ultrafiltration_B0 AS 
    SELECT T_final_lactate.*, ultrafiltration_0."ultrafiltration_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN ultrafiltration_0
    ON ultrafiltration_0.subject_id = T_final_lactate.subject_id
;

/*une fois que nous avons récupéré la variable "ultrafiltration_J0(mL)" pour tous les individus présent dans notre 
table 'T_final_lactate', nous refaisons une autre fusion entre cette vue et la vue ultrafiltration_1 pour étendre 
également la variable "ultrafiltration_J1(mL)" à patients présents dans la table 'T_final_lactate' en gardant la même 
phylosophie que celle utilisée pour la variable "ultrafiltration_J0(mL)". 
Donc,Les patients n'ayant pas eu d'ultrafiltration le lendemain de leur arrêt cardiaque auront une valeur nulle 
et les patients ayant eu effectivement une ultrafiltration le lendemain de leur arrêt cardiaque auront comme valeur
 de la variable "ultrafiltration_J1(mL)" la quantité totale qui leur a été donnée*/
CREATE OR REPLACE VIEW ultrafiltration_B1 AS
    SELECT ultrafiltration_B0.*, ultrafiltration_1."ultrafiltration_J1(mL)"
    FROM ultrafiltration_B0
    LEFT JOIN ultrafiltration_1
    ON ultrafiltration_1.subject_id = ultrafiltration_B0.subject_id
;

--Nous faisons de même pour les variables "ultrafiltration_J2(mL)" et "ultrafiltration_J3(mL)" .
--Notons que "ultrafiltration_J2(mL)" et "ultrafiltration_J3(mL)" mesurent respectivement les quantités totales d'ultrafiltration 
-- données aux patients 2 jours et 3 jours après leur arrêt cardiaque.
CREATE OR REPLACE VIEW ultrafiltration_B2 AS
    SELECT ultrafiltration_B1.*, ultrafiltration_2."ultrafiltration_J2(mL)"
    FROM ultrafiltration_B1
    LEFT JOIN ultrafiltration_2
    ON ultrafiltration_2.subject_id = ultrafiltration_B1.subject_id
;

CREATE OR REPLACE VIEW ultrafiltration_B3 AS
    SELECT ultrafiltration_B2.*, ultrafiltration_3."ultrafiltration_J3(mL)"
    FROM ultrafiltration_B2
    LEFT JOIN ultrafiltration_3
    ON ultrafiltration_3.subject_id = ultrafiltration_B2.subject_id
;

--Nous effectuons une jointure entre ultrafiltration_B3 et T_final_index_cardiac pour restreindre les variables aux individus ayant été en 
-- état de choc.
CREATE TABLE T_final_ultrafiltration AS 
    SELECT T_final_index_cardiac.*
    ,ultrafiltration_B3."ultrafiltration_J0(mL)"
    ,ultrafiltration_B3."ultrafiltration_J1(mL)"
    ,ultrafiltration_B3."ultrafiltration_J2(mL)"
    ,ultrafiltration_B3."ultrafiltration_J3(mL)"
    FROM T_final_index_cardiac 
    LEFT JOIN ultrafiltration_B3
    ON T_final_index_cardiac.subject_id = ultrafiltration_B3.subject_id
;   


----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*OR_urine*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "OR_urine_J0(mL)","OR_urine_J1(mL)","OR_urine_J2(mL)" et "OR_urine_J3(mL)" sont créées sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
   
CREATE OR REPLACE VIEW V_mesureOR_urine AS
    SELECT *
    FROM mimiciv_icu.outputevents out
    WHERE out.itemid = 226627;

CREATE OR REPLACE VIEW V_OR_urine AS
    SELECT sum(V_mesureOR_urine.value) value_sum
    ,V_mesureOR_urine.subject_id,date(V_mesureOR_urine.charttime) charttime
    FROM V_mesureOR_urine
    GROUP BY V_mesureOR_urine.subject_id, date(V_mesureOR_urine.charttime)
;

CREATE OR REPLACE VIEW OR_urine_0 AS 
SELECT T_final_lactate.*,V_OR_urine.value_sum "OR_urine_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_OR_urine
    ON V_OR_urine.subject_id = T_final_lactate.subject_id
    WHERE V_OR_urine.charttime = T_final_lactate.J0
;


CREATE OR REPLACE VIEW OR_urine_1 AS 
SELECT T_final_lactate.*,V_OR_urine.value_sum "OR_urine_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_OR_urine
    ON V_OR_urine.subject_id = T_final_lactate.subject_id
    WHERE V_OR_urine.charttime = T_final_lactate.J1
;


CREATE OR REPLACE VIEW OR_urine_2 AS 
SELECT T_final_lactate.*,V_OR_urine.value_sum "OR_urine_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_OR_urine
    ON V_OR_urine.subject_id = T_final_lactate.subject_id
    WHERE V_OR_urine.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW OR_urine_3 AS 
SELECT T_final_lactate.*,V_OR_urine.value_sum "OR_urine_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_OR_urine
    ON V_OR_urine.subject_id = T_final_lactate.subject_id
    WHERE V_OR_urine.charttime = T_final_lactate.J3
;


CREATE OR REPLACE VIEW OR_urine_B0 AS 
    SELECT T_final_lactate.*, OR_urine_0."OR_urine_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN OR_urine_0
    ON OR_urine_0.subject_id = T_final_lactate.subject_id
;


CREATE OR REPLACE VIEW OR_urine_B1 AS
    SELECT OR_urine_B0.*, OR_urine_1."OR_urine_J1(mL)"
    FROM OR_urine_B0
    LEFT JOIN OR_urine_1
    ON OR_urine_1.subject_id = OR_urine_B0.subject_id
;


CREATE OR REPLACE VIEW OR_urine_B2 AS
    SELECT OR_urine_B1.*, OR_urine_2."OR_urine_J2(mL)"
    FROM OR_urine_B1
    LEFT JOIN OR_urine_2
    ON OR_urine_2.subject_id = OR_urine_B1.subject_id
;


CREATE OR REPLACE VIEW OR_urine_B3 AS
    SELECT OR_urine_B2.*, OR_urine_3."OR_urine_J3(mL)"
    FROM OR_urine_B2
    LEFT JOIN OR_urine_3
    ON OR_urine_3.subject_id = OR_urine_B2.subject_id
;

CREATE TABLE T_final_OR_urine AS 
    SELECT T_final_ultrafiltration.*
    ,OR_urine_B3."OR_urine_J0(mL)"
    ,OR_urine_B3."OR_urine_J1(mL)"
    ,OR_urine_B3."OR_urine_J2(mL)"
    ,OR_urine_B3."OR_urine_J3(mL)"
    FROM T_final_ultrafiltration 
    LEFT JOIN OR_urine_B3
    ON T_final_ultrafiltration.subject_id = OR_urine_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*PACU_urine*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "PACU_urine_J0(mL)","PACU_urine_J1(mL)","PACU_urine_J2(mL)" et "PACU_urine_J3(mL)" sont créées sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
CREATE OR REPLACE VIEW V_mesurePACU_urine AS
    SELECT *
    FROM mimiciv_icu.outputevents out
    WHERE out.itemid = 226631;

CREATE OR REPLACE VIEW V_PACU_urine AS
    SELECT sum(V_mesurePACU_urine.value) value_sum
    ,V_mesurePACU_urine.subject_id,date(V_mesurePACU_urine.charttime) charttime
    FROM V_mesurePACU_urine
    GROUP BY V_mesurePACU_urine.subject_id, date(V_mesurePACU_urine.charttime)
;


CREATE OR REPLACE VIEW PACU_urine_0 AS 
SELECT t_final_lactate.*,V_PACU_urine.value_sum "PACU_urine_J0(mL)"
    FROM t_final_lactate
    LEFT JOIN V_PACU_urine
    ON V_PACU_urine.subject_id = t_final_lactate.subject_id
    WHERE V_PACU_urine.charttime = t_final_lactate.J0
;

CREATE OR REPLACE VIEW PACU_urine_1 AS 
SELECT t_final_lactate.*,V_PACU_urine.value_sum "PACU_urine_J1(mL)"
    FROM t_final_lactate
    LEFT JOIN V_PACU_urine
    ON V_PACU_urine.subject_id = t_final_lactate.subject_id
    WHERE V_PACU_urine.charttime = t_final_lactate.J1
;


CREATE OR REPLACE VIEW PACU_urine_2 AS 
SELECT t_final_lactate.*,V_PACU_urine.value_sum "PACU_urine_J2(mL)"
    FROM t_final_lactate
    LEFT JOIN V_PACU_urine
    ON V_PACU_urine.subject_id = t_final_lactate.subject_idca
    WHERE V_PACU_urine.charttime = t_final_lactate.J2
;


CREATE OR REPLACE VIEW PACU_urine_3 AS 
SELECT t_final_lactate.*,V_PACU_urine.value_sum "PACU_urine_J3(mL)"
    FROM t_final_lactate
    LEFT JOIN V_PACU_urine
    ON V_PACU_urine.subject_id = t_final_lactate.subject_id
    WHERE V_PACU_urine.charttime = t_final_lactate.J3
;

------------------
CREATE OR REPLACE VIEW PACU_urine_B0 AS 
    SELECT t_final_lactate.*, PACU_urine_0."PACU_urine_J0(mL)"
    FROM t_final_lactate
    LEFT JOIN PACU_urine_0
    ON PACU_urine_0.subject_id = t_final_lactate.subject_id
;

CREATE OR REPLACE VIEW PACU_urine_B1 AS
    SELECT PACU_urine_B0.*, PACU_urine_1."PACU_urine_J1(mL)"
    FROM PACU_urine_B0
    LEFT JOIN PACU_urine_1
    ON PACU_urine_1.subject_id = PACU_urine_B0.subject_id
;

CREATE OR REPLACE VIEW PACU_urine_B2 AS
    SELECT PACU_urine_B1.*, PACU_urine_2."PACU_urine_J2(mL)"
    FROM PACU_urine_B1
    LEFT JOIN PACU_urine_2
    ON PACU_urine_2.subject_id = PACU_urine_B1.subject_id
;

CREATE OR REPLACE VIEW PACU_urine_B3 AS
    SELECT PACU_urine_B2.*, PACU_urine_3."PACU_urine_J3(mL)"
    FROM PACU_urine_B2
    LEFT JOIN PACU_urine_3
    ON PACU_urine_3.subject_id = PACU_urine_B2.subject_id
;


CREATE TABLE T_final_PACU_urine AS 
    SELECT t_final_or_urine.*
    ,PACU_urine_B3."PACU_urine_J0(mL)"
    ,PACU_urine_B3."PACU_urine_J1(mL)"
    ,PACU_urine_B3."PACU_urine_J2(mL)"
    ,PACU_urine_B3."PACU_urine_J3(mL)"
    FROM t_final_or_urine 
    LEFT JOIN PACU_urine_B3
    ON t_final_or_urine.subject_id = PACU_urine_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*hemodialyse*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "hemodialyse_J0(mL)","hemodialyse_J1(mL)","hemodialyse_J2(mL)" et "hemodialyse_J3(mL)" sont créées sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
CREATE OR REPLACE VIEW V_mesurehemodialyse AS
   SELECT *
    FROM mimiciv_icu.chartevents char
    WHERE char.itemid = 226499;


CREATE OR REPLACE VIEW V_hemodialyse AS
    SELECT sum(V_mesurehemodialyse.valuenum) value_sum
    ,V_mesurehemodialyse.subject_id,date(V_mesurehemodialyse.charttime) charttime
    FROM V_mesurehemodialyse
    GROUP BY V_mesurehemodialyse.subject_id, date(V_mesurehemodialyse.charttime)
;

CREATE OR REPLACE VIEW hemodialyse_0 AS 
SELECT T_final_lactate.*,V_hemodialyse.value_sum "hemodialyse_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_hemodialyse
    ON V_hemodialyse.subject_id = T_final_lactate.subject_id
    WHERE V_hemodialyse.charttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW hemodialyse_1 AS 
SELECT T_final_lactate.*,V_hemodialyse.value_sum "hemodialyse_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_hemodialyse
    ON V_hemodialyse.subject_id = T_final_lactate.subject_id
    WHERE V_hemodialyse.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW hemodialyse_2 AS 
SELECT T_final_lactate.*,V_hemodialyse.value_sum "hemodialyse_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_hemodialyse
    ON V_hemodialyse.subject_id = T_final_lactate.subject_id
    WHERE V_hemodialyse.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW hemodialyse_3 AS 
SELECT T_final_lactate.*,V_hemodialyse.value_sum "hemodialyse_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_hemodialyse
    ON V_hemodialyse.subject_id = T_final_lactate.subject_id
    WHERE V_hemodialyse.charttime = T_final_lactate.J3
;

-----------------------------------------------------------------

CREATE OR REPLACE VIEW hemodialyse_B0 AS 
    SELECT T_final_lactate.*, hemodialyse_0."hemodialyse_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN hemodialyse_0
    ON hemodialyse_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW hemodialyse_B1 AS
    SELECT hemodialyse_B0.*, hemodialyse_1."hemodialyse_J1(mL)"
    FROM hemodialyse_B0
    LEFT JOIN hemodialyse_1
    ON hemodialyse_1.subject_id = hemodialyse_B0.subject_id
;
CREATE OR REPLACE VIEW hemodialyse_B2 AS
    SELECT hemodialyse_B1.*, hemodialyse_2."hemodialyse_J2(mL)"
    FROM hemodialyse_B1
    LEFT JOIN hemodialyse_2
    ON hemodialyse_2.subject_id = hemodialyse_B1.subject_id
;
CREATE OR REPLACE VIEW hemodialyse_B3 AS
    SELECT hemodialyse_B2.*, hemodialyse_3."hemodialyse_J3(mL)"
    FROM hemodialyse_B2
    LEFT JOIN hemodialyse_3
    ON hemodialyse_3.subject_id = hemodialyse_B2.subject_id
;


CREATE TABLE T_final_hemodialyse AS 
    SELECT T_final_pacu_urine.*
    ,hemodialyse_B3."hemodialyse_J0(mL)"
    ,hemodialyse_B3."hemodialyse_J1(mL)"
    ,hemodialyse_B3."hemodialyse_J2(mL)"
    ,hemodialyse_B3."hemodialyse_J3(mL)"
    FROM T_final_pacu_urine 
    LEFT JOIN hemodialyse_B3
    ON T_final_pacu_urine.subject_id = hemodialyse_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*cardiac output(thermodilution)*/
----------------------------------------------------------------------------------------------------------------------------------------
-- Nous devons selectionner les valeurs minimales et maximales par jour, les variables "thermodilutionCO_max_J3(L/min)","thermodilutionCO_max_J2(L/min)"
-- "thermodilutionCO_max_J1(L/min)","thermodilutionCO_max_J0(L/min)","thermodilutionCO_min_J3(L/min)","thermodilutionCO_min_J2(L/min)"
--"thermodilutionCO_min_J1(L/min)","thermodilutionCO_min_J0(L/min)" sont créées suivant la même logique que les variables "glycemie_max_J3(g/L)"
--"glycemie_max_J2(g/L)","glycemie_max_J1(g/L)","glycemie_max_J0(g/L)","glycemie_min_J3(g/L)","glycemie_min_J2(g/L)","glycemie_min_J1(g/L)"
--et "glycemie_min_J0(g/L)". La seule difference reside dans le fait que pour les variables glycemie, une conversion a été faite(les valeurs
-- etaient divisées par 100) alors que pour les variables de thermodilution, il n'y a pas eu de conversion.
CREATE OR REPLACE VIEW V_mesurethermodilutionCO_max AS
SELECT *
FROM mimiciv_icu.chartevents char
WHERE char.itemid = 220088;

CREATE OR REPLACE VIEW V_thermodilutionCO AS
    SELECT 
	max(V_mesurethermodilutionCO_max.valuenum) AS value_max
    ,min(V_mesurethermodilutionCO_max.valuenum) AS value_min
    ,V_mesurethermodilutionCO_max.subject_id,date(V_mesurethermodilutionCO_max.charttime) charttime
    FROM V_mesurethermodilutionCO_max
    GROUP BY V_mesurethermodilutionCO_max.subject_id, date(V_mesurethermodilutionCO_max.charttime)
;


CREATE OR REPLACE VIEW thermodilutionCO_max_0 as 
select T_final_lactate.*
    ,V_thermodilutionCO.value_max "thermodilutionCO_max_J0(L/min)"
    ,V_thermodilutionCO.value_min "thermodilutionCO_min_J0(L/min)"
    FROM T_final_lactate
    LEFT JOIN V_thermodilutionCO
    ON V_thermodilutionCO.subject_id = T_final_lactate.subject_id
    WHERE V_thermodilutionCO.charttime = T_final_lactate.J0
;

--SELECT * FROM thermodilutionCO_max_0;

CREATE OR REPLACE VIEW thermodilutionCO_max_1 
as select T_final_lactate.*
    ,V_thermodilutionCO.value_max "thermodilutionCO_max_J1(L/min)"
    ,V_thermodilutionCO.value_min "thermodilutionCO_min_J1(L/min)"
    FROM T_final_lactate
    LEFT JOIN V_thermodilutionCO
    ON V_thermodilutionCO.subject_id = T_final_lactate.subject_id
    WHERE V_thermodilutionCO.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW thermodilutionCO_max_2 
    as select T_final_lactate.*
    ,V_thermodilutionCO.value_max "thermodilutionCO_max_J2(L/min)"
    ,V_thermodilutionCO.value_min "thermodilutionCO_min_J2(L/min)"
    FROM T_final_lactate
    LEFT JOIN V_thermodilutionCO
    ON V_thermodilutionCO.subject_id = T_final_lactate.subject_id
    WHERE V_thermodilutionCO.charttime = T_final_lactate.J2
;


CREATE OR REPLACE VIEW thermodilutionCO_max_3 
as select T_final_lactate.*
    ,V_thermodilutionCO.value_max "thermodilutionCO_max_J3(L/min)"
    ,V_thermodilutionCO.value_min "thermodilutionCO_min_J3(L/min)"
    FROM T_final_lactate
    LEFT JOIN V_thermodilutionCO
    ON V_thermodilutionCO.subject_id = T_final_lactate.subject_id
    WHERE V_thermodilutionCO.charttime = T_final_lactate.J3
;

------------------Jointures------------------------------------------------------

CREATE OR REPLACE VIEW thermodilutionCO_max_B0 AS 
    SELECT T_final_lactate.*
    , thermodilutionCO_max_0."thermodilutionCO_max_J0(L/min)"
    , thermodilutionCO_max_0."thermodilutionCO_min_J0(L/min)"
    FROM T_final_lactate
    LEFT JOIN thermodilutionCO_max_0
    ON thermodilutionCO_max_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW thermodilutionCO_max_B1 AS
    SELECT thermodilutionCO_max_B0.*
    , thermodilutionCO_max_1."thermodilutionCO_max_J1(L/min)"
    , thermodilutionCO_max_1."thermodilutionCO_min_J1(L/min)"
    FROM thermodilutionCO_max_B0
    LEFT JOIN thermodilutionCO_max_1
    ON thermodilutionCO_max_1.subject_id = thermodilutionCO_max_B0.subject_id
;

CREATE OR REPLACE VIEW thermodilutionCO_max_B2 AS
    SELECT thermodilutionCO_max_B1.*
    , thermodilutionCO_max_2."thermodilutionCO_max_J2(L/min)"
    , thermodilutionCO_max_2."thermodilutionCO_min_J2(L/min)"
    FROM thermodilutionCO_max_B1
    LEFT JOIN thermodilutionCO_max_2
    ON thermodilutionCO_max_2.subject_id = thermodilutionCO_max_B1.subject_id
;

CREATE OR REPLACE VIEW thermodilutionCO_max_B3 AS
    SELECT thermodilutionCO_max_B2.*
    , thermodilutionCO_max_3."thermodilutionCO_max_J3(L/min)"
    , thermodilutionCO_max_3."thermodilutionCO_min_J3(L/min)"
    FROM thermodilutionCO_max_B2
    LEFT JOIN thermodilutionCO_max_3
    ON thermodilutionCO_max_3.subject_id = thermodilutionCO_max_B2.subject_id
;

CREATE TABLE T_final_thermodilutionCO AS 
    SELECT T_final_hemodialyse.*
	,thermodilutionCO_max_B3."thermodilutionCO_max_J3(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_max_J2(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_max_J1(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_max_J0(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_min_J3(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_min_J2(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_min_J1(L/min)"
	,thermodilutionCO_max_B3."thermodilutionCO_min_J0(L/min)"
    FROM T_final_hemodialyse
    LEFT JOIN thermodilutionCO_max_B3
    ON T_final_hemodialyse.subject_id = thermodilutionCO_max_B3.subject_id
;

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Platelets*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "platelets_J0(mL)","platelets_J1(mL)","platelets_J2(mL)" et "platelets_J3(mL)" sont créées sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
CREATE OR REPLACE VIEW V_mesureplatelets AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =225170
;


CREATE OR REPLACE VIEW V_platelets_final AS
    SELECT sum(V_mesureplatelets.amount) sum_platelets,
            V_mesureplatelets.subject_id,
            date(V_mesureplatelets.starttime) starttime
    FROM V_mesureplatelets
    GROUP BY V_mesureplatelets.subject_id, date(V_mesureplatelets.starttime)
;

CREATE OR REPLACE VIEW platelets_0 AS 
SELECT T_final_lactate.*
,V_platelets_final.sum_platelets AS "platelets_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_platelets_final
    ON V_platelets_final.subject_id = T_final_lactate.subject_id
    WHERE V_platelets_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW platelets_1 AS 
SELECT T_final_lactate.*
,V_platelets_final.sum_platelets AS "platelets_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_platelets_final
    ON V_platelets_final.subject_id = T_final_lactate.subject_id
    WHERE V_platelets_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW platelets_2 AS 
SELECT T_final_lactate.*
,V_platelets_final.sum_platelets AS "platelets_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_platelets_final
    ON V_platelets_final.subject_id = T_final_lactate.subject_id
    WHERE V_platelets_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW platelets_3 AS 
SELECT T_final_lactate.*
,V_platelets_final.sum_platelets AS "platelets_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_platelets_final
    ON V_platelets_final.subject_id = T_final_lactate.subject_id
    WHERE V_platelets_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW platelets_B0 AS 
    SELECT T_final_lactate.*, platelets_0."platelets_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN platelets_0
    ON platelets_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW platelets_B1 AS 
    SELECT platelets_B0.*, platelets_1."platelets_J1(mL)"
    FROM platelets_B0
    LEFT JOIN platelets_1
    ON platelets_1.subject_id = platelets_B0.subject_id
;

CREATE OR REPLACE VIEW platelets_B2 AS 
    SELECT platelets_B1.*, platelets_2."platelets_J2(mL)"
    FROM platelets_B1
    LEFT JOIN platelets_2
    ON platelets_2.subject_id = platelets_B1.subject_id
;

CREATE OR REPLACE VIEW platelets_B3 AS 
    SELECT platelets_B2.*, platelets_3."platelets_J3(mL)"
    FROM platelets_B2
    LEFT JOIN platelets_3
    ON platelets_3.subject_id = platelets_B2.subject_id
;

CREATE TABLE T_final_platelets AS 
    SELECT T_final_thermodilutionCO.*
    ,platelets_B3."platelets_J0(mL)"
    ,platelets_B3."platelets_J1(mL)"
    ,platelets_B3."platelets_J2(mL)"
    ,platelets_B3."platelets_J3(mL)"
    FROM T_final_thermodilutionCO 
    LEFT JOIN platelets_B3
    ON T_final_thermodilutionCO.subject_id = platelets_B3.subject_id
;   

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Fresh Frozen Plasma*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "FF_plasmas_J0(mL)","FF_plasmas_J1(mL)","FF_plasmas_J2(mL)" et "FF_plasmas_J3(mL)" sont créées sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
CREATE OR REPLACE VIEW V_mesureFF_plasmas AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid =220970
;

CREATE OR REPLACE VIEW V_FF_plasmas_final AS
    SELECT sum(V_mesureFF_plasmas.amount) sum_FF_plasmas,
            V_mesureFF_plasmas.subject_id,
            date(V_mesureFF_plasmas.starttime) starttime
    FROM V_mesureFF_plasmas
    GROUP BY V_mesureFF_plasmas.subject_id, date(V_mesureFF_plasmas.starttime)
;

CREATE OR REPLACE VIEW FF_plasmas_0 AS
 SELECT T_final_lactate.*
,V_FF_plasmas_final.sum_FF_plasmas AS "FF_plasmas_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_FF_plasmas_final
    ON V_FF_plasmas_final.subject_id = T_final_lactate.subject_id
    WHERE V_FF_plasmas_final.starttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW FF_plasmas_1 AS 
SELECT T_final_lactate.*
,V_FF_plasmas_final.sum_FF_plasmas AS "FF_plasmas_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_FF_plasmas_final
    ON V_FF_plasmas_final.subject_id = T_final_lactate.subject_id
    WHERE V_FF_plasmas_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW FF_plasmas_2 AS 
SELECT T_final_lactate.*
,V_FF_plasmas_final.sum_FF_plasmas AS "FF_plasmas_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_FF_plasmas_final
    ON V_FF_plasmas_final.subject_id = T_final_lactate.subject_id
    WHERE V_FF_plasmas_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW FF_plasmas_3 AS 
SELECT T_final_lactate.*
,V_FF_plasmas_final.sum_FF_plasmas AS "FF_plasmas_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_FF_plasmas_final
    ON V_FF_plasmas_final.subject_id = T_final_lactate.subject_id
    WHERE V_FF_plasmas_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW FF_plasmas_B0 AS 
    SELECT T_final_lactate.*, FF_plasmas_0."FF_plasmas_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN FF_plasmas_0
    ON FF_plasmas_0.subject_id = T_final_lactate.subject_id
;
CREATE OR REPLACE VIEW FF_plasmas_B1 AS 
    SELECT FF_plasmas_B0.*, FF_plasmas_1."FF_plasmas_J1(mL)"
    FROM FF_plasmas_B0
    LEFT JOIN FF_plasmas_1
    ON FF_plasmas_1.subject_id = FF_plasmas_B0.subject_id
;

CREATE OR REPLACE VIEW FF_plasmas_B2 AS 
    SELECT FF_plasmas_B1.*, FF_plasmas_2."FF_plasmas_J2(mL)"
    FROM FF_plasmas_B1
    LEFT JOIN FF_plasmas_2
    ON FF_plasmas_2.subject_id = FF_plasmas_B1.subject_id
;

CREATE OR REPLACE VIEW FF_plasmas_B3 AS 
    SELECT FF_plasmas_B2.*, FF_plasmas_3."FF_plasmas_J3(mL)"
    FROM FF_plasmas_B2
    LEFT JOIN FF_plasmas_3
    ON FF_plasmas_3.subject_id = FF_plasmas_B2.subject_id
;

CREATE TABLE T_final_FF_plasmas AS 
    SELECT T_final_platelets.*
    ,FF_plasmas_B3."FF_plasmas_J0(mL)"
    ,FF_plasmas_B3."FF_plasmas_J1(mL)"
    ,FF_plasmas_B3."FF_plasmas_J2(mL)"
    ,FF_plasmas_B3."FF_plasmas_J3(mL)"
    FROM T_final_platelets 
    LEFT JOIN FF_plasmas_B3
    ON T_final_platelets.subject_id = FF_plasmas_B3.subject_id
;   
----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Ventilation*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Pour identifier les individus ayant eu une ventilation mécanique, nous avons recherché dans les procédures, celles qui ont nécéssité une
une ventilation mécanique. Cependant, dans la table 'procedures_icd' dans laquelle les codes des procédures sont décrites selon les normes
internationales, selon la version le code des procédures changent. Ainsi, nous avons d'abord créer la variable 'icd9_code' qui 
récupère le code de la procédure si la version est 9 et attribut la valeur NULL sinon. La variable 'icd10_code' fut construite de la même
facon.*/
CREATE TABLE proce AS (
    SELECT
        hadm_id
        , CASE WHEN icd_version = 9 THEN icd_code ELSE NULL END AS icd9_code
        , CASE WHEN icd_version = 10 THEN icd_code ELSE NULL END AS icd10_code
	  ,subject_id
    FROM mimiciv_hosp.procedures_icd
);

--Ensuite, nous avons créé dans la table 'com_venti' une variable indicatrice qui prend la valeur 1 si l'individu a une procédure nécéssitant 
--une ventilation mécanique et 0 sinon.
CREATE TABLE com_venti AS (
    SELECT
        pro.hadm_id
        , MAX(CASE WHEN icd9_code = '9671' THEN 1 ELSE 0 END) AS ventilation_procedure
    FROM mimiciv_hosp.procedures_icd pro
    LEFT JOIN proce
    ON pro.hadm_id = proce.hadm_id and pro.subject_id = proce.subject_id
    GROUP BY pro.hadm_id 
);


----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Comorbidités*/
----------------------------------------------------------------------------------------------------------------------------------------
/*La recherche des comorbidités des patients est très importante pour le reste de l'étude. Cependant, aucune variable ne nous renseigne 
directement sur ces dernières. Nous avons une liste pas exhaustive de comorbidités(obesity:obesité,liver_disease:maladie hepatique,
diabetes:diabètes,renal_disease:maladie rénale,malignant_cancer:cancer,aids:Sida,heart_failure:maladie cardiaque,
chronic_pulmonary_disease:maladie pulmunaire).Comme alternative, nous parcourons l'ensemble des diagnostics des patients afin de voir 
s'ils ont eu dans leur diagnostic une des comorbités listée plus haut. 
*/

-- Nous avons créé, également, les variables icd9_code et icd10_code des diagnostics selon le même principe que icd9_code et icd10_code des procédures
CREATE TABLE diag AS (
    SELECT
        hadm_id
        , CASE WHEN icd_version = 9 THEN icd_code ELSE NULL END AS icd9_code
        , CASE WHEN icd_version = 10 THEN icd_code ELSE NULL END AS icd10_code
	  ,subject_id
    FROM mimiciv_hosp.diagnoses_icd
);

--Nous parcourons l'ensemble des diagnostics et si l'une des comorbodités apparait dans le diagnostic, nous codons 1 et 0 si elle n'est pas dans
-- le diagnostic.
CREATE TABLE com AS (
    SELECT
        ad.hadm_id
	
        -- heart failure
        , MAX(CASE WHEN
            SUBSTR(icd10_code, 1, 6) in ('I97130','I97131')
            OR
            SUBSTR(icd10_code, 1, 5) in ('I9713','I0981')
            OR
            SUBSTR(icd9_code, 1, 5) = '39891'--heart failure
            OR
            --Congestive heart failure
            SUBSTR(icd9_code, 1, 3) = '428'
            OR
            SUBSTR(
                icd9_code, 1, 5
            ) IN ('39891', '40201', '40211', '40291', '40401', '40403'
                , '40411', '40413', '40491', '40493')
            OR
            SUBSTR(icd9_code, 1, 4) BETWEEN '4254' AND '4259'
            OR
            SUBSTR(icd10_code, 1, 3) IN ('I43', 'I50')
            OR
            SUBSTR(
                icd10_code, 1, 4
            ) IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420'
                  , 'I425', 'I426', 'I427', 'I428', 'I429', 'P290'
            )
            THEN 1
            ELSE 0 END) AS heart_failure

        -- Obesity
        ,MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 5) BETWEEN '64910' AND '64914'
            OR
            SUBSTR(icd9_code, 1, 5) in ('27800','27801','27803')
            OR
            icd9_code='V778'
            OR
            SUBSTR(icd10_code, 1, 6) BETWEEN 'O99210' AND 'O99215'
            OR
            SUBSTR(icd10_code, 1, 5) = ('O9921') 
            OR
            SUBSTR(icd10_code, 1, 5) in('E6609','E6601')
            OR
            icd10_code='E66'
            OR
            SUBSTR(icd10_code, 1, 4) in ('E660','E661','E662','E668','E669')
            
            THEN 1
            ELSE 0
            END) AS obesity 

       -- Cause arret cardiaque
       ,MAX(
        CASE 
            WHEN (icd9_code='V1253' OR icd10_code = 'Z8674') then 'Cardiac'
            /*WHEN (icd10_code in ('I469','O0881','O2911','O29112','I97121','I46','I97120','I97710','I9712','O0336','O29119','O0486',
                'O29113','P2981','I468','I462','I97711','I9771','O0736','O29111','O0386')
                OR 
            icd9_code in ('4275','77985')
            ) THEN 'Non_cardiac'*/
            ELSE 'Non_cardiac'
       END) AS cause_arret_cardiac


        -- Chronic pulmonary disease
        , MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 3) BETWEEN '490' AND '505'
            OR
            SUBSTR(icd9_code, 1, 4) IN ('4168', '4169', '5064', '5081', '5088')
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'J40' AND 'J47'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'J60' AND 'J67'
            OR
            SUBSTR(icd10_code, 1, 4) IN ('I278', 'I279', 'J684', 'J701', 'J703')
            THEN 1
            ELSE 0 END) AS chronic_pulmonary_disease

        --  liver disease
        , MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 3) IN ('570', '571')
            OR
            SUBSTR(
                icd9_code, 1, 4
            ) IN ('0706', '0709', '5733', '5734', '5738', '5739', 'V427')
            OR
            SUBSTR(
                icd9_code, 1, 5
            ) IN ('07022', '07023', '07032', '07033', '07044', '07054')
            OR
            SUBSTR(icd10_code, 1, 3) IN ('B18', 'K73', 'K74')
            OR
            SUBSTR(
                icd10_code, 1, 4
            ) IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K713'
                  , 'K714', 'K715', 'K717', 'K760', 'K762'
                  , 'K763', 'K764', 'K768', 'K769', 'Z944')
            OR
             SUBSTR(icd9_code, 1, 4) IN ('4560', '4561', '4562')
            OR
            SUBSTR(icd9_code, 1, 4) BETWEEN '5722' AND '5728'
            OR
            SUBSTR(
                icd10_code, 1, 4
            ) IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711'
                  , 'K721', 'K729', 'K765', 'K766', 'K767')      
            THEN 1
            ELSE 0 END) AS liver_disease

        -- Diabetes 
        , MAX(CASE WHEN
            SUBSTR(
                icd9_code, 1, 4
            ) IN ('2500', '2501', '2502', '2503', '2508', '2509')
            OR
            SUBSTR(
                icd10_code, 1, 4
            ) IN ('E100', 'E10l', 'E106', 'E108', 'E109', 'E110', 'E111'
                  , 'E116'
                  , 'E118'
                  , 'E119'
                  , 'E120'
                  , 'E121'
                  , 'E126'
                  , 'E128'
                  , 'E129'
                  , 'E130'
                  , 'E131'
                  , 'E136'
                  , 'E138'
                  , 'E139'
                  , 'E140'
                  , 'E141', 'E146', 'E148', 'E149')
            OR
            SUBSTR(icd9_code, 1, 4) IN ('2504', '2505', '2506', '2507')
            OR
            SUBSTR(
                icd10_code, 1, 4
            ) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113'
                  , 'E114'
                  , 'E115'
                  , 'E117'
                  , 'E122'
                  , 'E123'
                  , 'E124'
                  , 'E125'
                  , 'E127'
                  , 'E132'
                  , 'E133'
                  , 'E134'
                  , 'E135'
                  , 'E137'
                  , 'E142'
                  , 'E143', 'E144', 'E145', 'E147')      
            THEN 1
            ELSE 0 END) AS diabetes


        -- Renal disease
        , MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 3) IN ('582', '585', '586', 'V56')
            OR
            SUBSTR(icd9_code, 1, 4) IN ('5880', 'V420', 'V451')
            OR
            SUBSTR(icd9_code, 1, 4) BETWEEN '5830' AND '5837'
            OR
            SUBSTR(
                icd9_code, 1, 5
            ) IN (
                '40301'
                , '40311'
                , '40391'
                , '40402'
                , '40403'
                , '40412'
                , '40413'
                , '40492'
                , '40493'
            )
            OR
            SUBSTR(icd10_code, 1, 3) IN ('N18', 'N19')
            OR
            SUBSTR(icd10_code, 1, 4) IN ('I120', 'I131', 'N032', 'N033', 'N034'
                                         , 'N035'
                                         , 'N036'
                                         , 'N037'
                                         , 'N052'
                                         , 'N053'
                                         , 'N054'
                                         , 'N055'
                                         , 'N056'
                                         , 'N057'
                                         , 'N250'
                                         , 'Z490'
                                         , 'Z491'
                                         , 'Z492'
                                         , 'Z940'
                                         , 'Z992'
            )
            THEN 1
            ELSE 0 END) AS renal_disease

        --Toute tumeur maligne, y compris les lymphomes et les leucémies,
        -- à l'exception des néoplasmes malins de la peau
    
        , MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 3) BETWEEN '140' AND '172'
            OR
            SUBSTR(icd9_code, 1, 4) BETWEEN '1740' AND '1958'
            OR
            SUBSTR(icd9_code, 1, 3) BETWEEN '200' AND '208'
            OR
            SUBSTR(icd9_code, 1, 4) = '2386'
            OR
            SUBSTR(icd10_code, 1, 3) IN ('C43', 'C88')
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C00' AND 'C26'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C30' AND 'C34'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C37' AND 'C41'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C45' AND 'C58'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C60' AND 'C76'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C81' AND 'C85'
            OR
            SUBSTR(icd10_code, 1, 3) BETWEEN 'C90' AND 'C97'
            THEN 1
            ELSE 0 END) AS malignant_cancer

        -- AIDS/HIV
        , MAX(CASE WHEN
            SUBSTR(icd9_code, 1, 3) IN ('042', '043', '044')
            OR
            SUBSTR(icd10_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24')
            THEN 1
            ELSE 0 END) AS aids
    FROM mimiciv_hosp.admissions ad
    LEFT JOIN diag
        ON ad.hadm_id = diag.hadm_id and ad.subject_id = diag.subject_id
    GROUP BY ad.hadm_id 
);


--- fusion
--On effectue dans un premier temps, une jointure entre la table 'T_final_FF_plasmas' obtenue dernièrement et la table 'com_venti'
-- dans le but d'ajouter la variable 'ventilation_procedure' de la table 'com_venti' aux variables de la table 'T_final_FF_plasmas'.
--Nous avons utiliser une 'INNER JOIN' car les individus qui se trouvent dans 'T_final_FF_plasmas' se trouvent dans la table 
--'com_venti'(en effet, la variable 'ventilation_procedure' a été créée pour tous les individus)
--Ensuite, on effectue une jointure entre la table obtenue précédemment 'T_finalbase_ile' avec la table 'com' qui contient les variables 
--indicatrices des comorbidités.
CREATE TABLE T_finalbase_utile AS
    SELECT T_final_FF_plasmas.*
    ,com.heart_failure
    ,com.obesity
    ,com.chronic_pulmonary_disease
    ,com.liver_disease
    ,com.diabetes
    ,com.renal_disease
    ,com.malignant_cancer
    ,com.aids   
 
    FROM T_final_FF_plasmas 
    INNER JOIN com 
    ON  com.hadm_id=T_final_FF_plasmas.hadm_id
;

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*PaO2/FiO2*/
----------------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE bg AS (
    SELECT
    -- specimen_id n'a jamais qu'une seule mesure pour chaque itemid
    -- nous pouvons donc simplement réduire les lignes en utilisant MAX()
        MAX(subject_id) AS subject_id
        , MAX(hadm_id) AS hadm_id
        , MAX(charttime) AS charttime
        -- specimen_id *peut* avoir des durées de stockage différentes, donc ceci
        -- prend la dernière
        , MAX(storetime) AS storetime
        , le.specimen_id
        , MAX(CASE WHEN itemid = 52033 THEN value ELSE NULL END) AS specimen
        , MAX(CASE WHEN itemid = 50801 THEN valuenum ELSE NULL END) AS aado2
        , MAX(CASE WHEN itemid = 50804 THEN valuenum ELSE NULL END) AS totalco2

        , MAX(CASE WHEN itemid = 50815 THEN valuenum ELSE NULL END) AS o2flow
 
        , MAX(CASE WHEN itemid = 50816 THEN
                CASE
                    WHEN valuenum > 20 AND valuenum <= 100 THEN valuenum
                    WHEN
                        valuenum > 0.2 AND valuenum <= 1.0 THEN valuenum * 100.0
                    ELSE NULL END
            ELSE NULL END) AS fio2
        , MAX(
            CASE
                WHEN itemid = 50817 AND valuenum <= 100 THEN valuenum ELSE NULL
            END
        ) AS so2
        , MAX(CASE WHEN itemid = 50818 THEN valuenum ELSE NULL END) AS pco2
        , MAX(CASE WHEN itemid = 50821 THEN valuenum ELSE NULL END) AS po2
        , MAX(
            CASE WHEN itemid = 50823 THEN valuenum ELSE NULL END
        ) AS requiredo2
    FROM mimiciv_hosp.labevents le
    WHERE le.itemid IN
       52033,
       50801,
       50804,
       50815,
       50816,
       50817,
       50818,
       50821,
       50823
        )
    GROUP BY le.specimen_id
);

CREATE TABLE stg_spo2 AS (
    SELECT subject_id, charttime
        -- la valeur moyenne est utilisée pour regrouper la SpO2 par heure du graphique
        , AVG(valuenum) AS spo2
    FROM mimiciv_icu.chartevents
    WHERE itemid = 220277 -- O2 saturation pulseoxymetry
        AND valuenum > 0 AND valuenum <= 100
    GROUP BY subject_id, charttime
);

CREATE TABLE stg_fio2 AS (
    SELECT subject_id, charttime
       -- prétraiter les FiO2 pour s'assurer qu'elles se situent entre 21 et 100 %.
        , MAX(
            CASE
                WHEN valuenum > 0.2 AND valuenum <= 1
                    THEN valuenum * 100
                -- données mal saisies - on dirait que le débit d'O2 est exprimé en litres
                WHEN valuenum > 1 AND valuenum < 20
                    THEN NULL
                WHEN valuenum >= 20 AND valuenum <= 100
                    THEN valuenum
                ELSE NULL END
        ) AS fio2_chartevents
    FROM mimiciv_icu.chartevents
    WHERE itemid = 223835 -- Inspired O2 Fraction (FiO2)
        AND valuenum > 0 AND valuenum <= 100
    GROUP BY subject_id, charttime
);


CREATE TABLE stg2 AS (
    SELECT bg.*
        , ROW_NUMBER() OVER (
            PARTITION BY bg.subject_id, bg.charttime ORDER BY s1.charttime DESC
        ) AS lastrowspo2
        , s1.spo2
    FROM bg
    LEFT JOIN stg_spo2 s1
    -- même hospitalisation
        ON bg.subject_id = s1.subject_id
           -- spo2 a eu lieu au maximum 2 heures avant ce gaz sanguin
            AND s1.charttime
            BETWEEN bg.charttime::timestamp - INTERVAL '2 hour'
            AND bg.charttime
    WHERE bg.po2 IS NOT NULL
);

CREATE TABLE stg3 AS (
    SELECT bg.*
        , ROW_NUMBER() OVER (
            PARTITION BY bg.subject_id, bg.charttime ORDER BY s2.charttime DESC
        ) AS lastrowfio2
        , s2.fio2_chartevents
    FROM stg2 bg
    LEFT JOIN stg_fio2 s2
        -- même patient
        ON bg.subject_id = s2.subject_id
            -- La fio2 est apparue au maximum 4 heures avant ce gaz du sang.
            AND s2.charttime >=bg.charttime::timestamp -  INTERVAL '4' HOUR
            AND s2.charttime <= bg.charttime
            AND s2.fio2_chartevents > 0
   -- seulement la ligne avec la SpO2 la plus récente (si aucune SpO2 n'a été trouvée lastRowSpO2 = 1)
    WHERE bg.lastrowspo2 = 1
);

CREATE OR REPLACE VIEW V_PaO2_FiO2_final 
    AS SELECT
    stg3.subject_id
    , stg3.hadm_id
    , stg3.charttime
   -- texte déroulant indiquant le type de spécimen
    , specimen

  -- paramètres liés à l'oxygène
    , so2
    , po2
    , pco2
    , fio2_chartevents, fio2
    , aado2
 -- calcule également l'AADO2
    , CASE
        WHEN po2 IS NULL
            OR pco2 IS NULL
            THEN NULL
        WHEN fio2 IS NOT NULL
           -- multiple par 100 car fio2 est en % mais devrait être une fraction
            THEN (fio2 / 100) * (760 - 47) - (pco2 / 0.8) - po2
        WHEN fio2_chartevents IS NOT NULL
            THEN (fio2_chartevents / 100) * (760 - 47) - (pco2 / 0.8) - po2
        ELSE NULL
    END AS aado2_calc
    , CASE
        WHEN po2 IS NULL
            THEN NULL
        WHEN fio2 IS NOT NULL
          -- multiplier par 100 car fio2 est en % mais devrait être une fraction
            THEN 100 * po2 / fio2
        WHEN fio2_chartevents IS NOT NULL
           -- multiplier par 100 car fio2 est en % mais devrait être une fraction
            THEN 100 * po2 / fio2_chartevents
        ELSE NULL
    END AS pao2fio2ratio
  
FROM stg3
WHERE lastrowfio2 = 1 -- seulement la FiO2 la plus récente
;

--------------------------------------------------------------
-- Nous devons selectionner les valeurs journalières minimales et maximales du rapport Pa02/Fi02.
--Les variables "PaO2_FiO2_max_J3(L/min)","PaO2_FiO2_max_J2(L/min)","PaO2_FiO2_max_J1(L/min)","PaO2_FiO2_max_J0(L/min)",
--"PaO2_FiO2_min_J3(L/min)","PaO2_FiO2_min_J2(L/min)","PaO2_FiO2_min_J1(L/min)","PaO2_FiO2_min_J0(L/min)" sont crées suivant le même principe que les variables "thermodilutionCO_max_J3(g/L)"
--"thermodilutionCO_max_J2(g/L)","thermodilutionCO_max_J1(g/L)","thermodilutionCO_max_J0(g/L)","thermodilutionCO_min_J3(g/L)","thermodilutionCO_min_J2(g/L)","thermodilutionCO_min_J1(g/L)"
--et "thermodilutionCO_min_J0(g/L)".

CREATE OR REPLACE VIEW V_PaO2_FiO2 AS
SELECT 
max(V_PaO2_FiO2_final.pao2fio2ratio) value_max,
min(V_PaO2_FiO2_final.pao2fio2ratio) value_min,
V_PaO2_FiO2_final.subject_id,V_PaO2_FiO2_final.hadm_id,
date(V_PaO2_FiO2_final.charttime) charttime
    FROM V_PaO2_FiO2_final
    GROUP BY V_PaO2_FiO2_final.subject_id,V_PaO2_FiO2_final.hadm_id,date(V_PaO2_FiO2_final.charttime)
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_0 AS 
SELECT T_final_lactate.*
    ,V_PaO2_FiO2.value_max "PaO2_FiO2_max_J0"
    ,V_PaO2_FiO2.value_min "PaO2_FiO2_min_J0"
    FROM T_final_lactate
    LEFT JOIN V_PaO2_FiO2
    ON V_PaO2_FiO2.subject_id = T_final_lactate.subject_id AND V_PaO2_FiO2.hadm_id = T_final_lactate.hadm_id
    WHERE V_PaO2_FiO2.charttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_1 AS 
SELECT T_final_lactate.*
    ,V_PaO2_FiO2.value_max "PaO2_FiO2_max_J1"
    ,V_PaO2_FiO2.value_min "PaO2_FiO2_min_J1"
    FROM T_final_lactate
    LEFT JOIN V_PaO2_FiO2
    ON V_PaO2_FiO2.subject_id = T_final_lactate.subject_id and V_PaO2_FiO2.hadm_id = T_final_lactate.hadm_id
    WHERE V_PaO2_FiO2.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_2 AS 
SELECT T_final_lactate.*
,V_PaO2_FiO2.value_max "PaO2_FiO2_max_J2"
,V_PaO2_FiO2.value_min "PaO2_FiO2_min_J2"
    FROM T_final_lactate
    LEFT JOIN V_PaO2_FiO2
    ON V_PaO2_FiO2.subject_id = T_final_lactate.subject_id and V_PaO2_FiO2.hadm_id = T_final_lactate.hadm_id
    WHERE V_PaO2_FiO2.charttime = T_final_lactate.J2
;


CREATE OR REPLACE VIEW PaO2_FiO2_max_3 AS 
SELECT T_final_lactate.*
,V_PaO2_FiO2.value_max "PaO2_FiO2_max_J3"
,V_PaO2_FiO2.value_min "PaO2_FiO2_min_J3"
    FROM T_final_lactate
    LEFT JOIN V_PaO2_FiO2
    ON V_PaO2_FiO2.subject_id = T_final_lactate.subject_id and V_PaO2_FiO2.hadm_id = T_final_lactate.hadm_id
    WHERE V_PaO2_FiO2.charttime = T_final_lactate.J3
;

------------------------------Jointures------------------------------------------


CREATE OR REPLACE VIEW PaO2_FiO2_max_B0 AS 
    SELECT T_final_lactate.*
    , PaO2_FiO2_max_0."PaO2_FiO2_max_J0"
    , PaO2_FiO2_max_0."PaO2_FiO2_min_J0"
    FROM T_final_lactate
    LEFT JOIN PaO2_FiO2_max_0
    ON PaO2_FiO2_max_0.subject_id = T_final_lactate.subject_id and PaO2_FiO2_max_0.hadm_id = T_final_lactate.hadm_id
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_B1 AS
    SELECT PaO2_FiO2_max_B0.*
    , PaO2_FiO2_max_1."PaO2_FiO2_max_J1"
    , PaO2_FiO2_max_1."PaO2_FiO2_min_J1"
    FROM PaO2_FiO2_max_B0
    LEFT JOIN PaO2_FiO2_max_1
    ON PaO2_FiO2_max_1.subject_id = PaO2_FiO2_max_B0.subject_id and PaO2_FiO2_max_1.hadm_id = PaO2_FiO2_max_B0.hadm_id
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_B2 AS
    SELECT PaO2_FiO2_max_B1.*
    , PaO2_FiO2_max_2."PaO2_FiO2_max_J2"
    , PaO2_FiO2_max_2."PaO2_FiO2_min_J2"
    FROM PaO2_FiO2_max_B1
    LEFT JOIN PaO2_FiO2_max_2
    ON PaO2_FiO2_max_2.subject_id = PaO2_FiO2_max_B1.subject_id and PaO2_FiO2_max_2.hadm_id = PaO2_FiO2_max_B1.hadm_id
;

CREATE OR REPLACE VIEW PaO2_FiO2_max_B3 AS
    SELECT PaO2_FiO2_max_B2.*
    , PaO2_FiO2_max_3."PaO2_FiO2_max_J3"
    , PaO2_FiO2_max_3."PaO2_FiO2_min_J3"
    FROM PaO2_FiO2_max_B2
    LEFT JOIN PaO2_FiO2_max_3
    ON PaO2_FiO2_max_3.subject_id = PaO2_FiO2_max_B2.subject_id and PaO2_FiO2_max_3.hadm_id = PaO2_FiO2_max_B2.hadm_id
;

CREATE TABLE T_final_PaO2_FiO2 AS 
    SELECT T_finalbase_utile.*
	,PaO2_FiO2_max_B3."PaO2_FiO2_max_J3"
	,PaO2_FiO2_max_B3."PaO2_FiO2_max_J2"
	,PaO2_FiO2_max_B3."PaO2_FiO2_max_J1"
	,PaO2_FiO2_max_B3."PaO2_FiO2_max_J0"
	,PaO2_FiO2_max_B3."PaO2_FiO2_min_J3"
	,PaO2_FiO2_max_B3."PaO2_FiO2_min_J2"
	,PaO2_FiO2_max_B3."PaO2_FiO2_min_J1"
	,PaO2_FiO2_max_B3."PaO2_FiO2_min_J0"
    FROM T_finalbase_utile
    LEFT JOIN PaO2_FiO2_max_B3
    ON T_finalbase_utile.subject_id = PaO2_FiO2_max_B3.subject_id and  T_finalbase_utile.hadm_id = PaO2_FiO2_max_B3.hadm_id
;

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*Urine output*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "urine_output_J0(mL)","urine_output_J1(mL)","urine_output_J2(mL)" et "urine_output_J3(mL)" sont créees sur le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)"*/
CREATE OR REPLACE VIEW V_mesureurine_output AS
    SELECT *
    FROM mimiciv_hosp.labevents out
    WHERE out.itemid = 51108
;

CREATE OR REPLACE VIEW V_urine_output AS
    SELECT sum(V_mesureurine_output.valuenum) value_sum,V_mesureurine_output.subject_id,date(V_mesureurine_output.charttime) charttime
    FROM V_mesureurine_output
    GROUP BY V_mesureurine_output.subject_id, date(V_mesureurine_output.charttime)
;

CREATE OR REPLACE VIEW urine_output_0 AS 
SELECT T_final_lactate.*,V_urine_output.value_sum "urine_output_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_urine_output
    ON V_urine_output.subject_id = T_final_lactate.subject_id
    WHERE V_urine_output.charttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW urine_output_1 AS 
SELECT T_final_lactate.*,V_urine_output.value_sum "urine_output_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_urine_output
    ON V_urine_output.subject_id = T_final_lactate.subject_id
    WHERE V_urine_output.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW urine_output_2 AS 
SELECT T_final_lactate.*,V_urine_output.value_sum "urine_output_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_urine_output
    ON V_urine_output.subject_id = T_final_lactate.subject_id
    WHERE V_urine_output.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW urine_output_3 AS 
SELECT T_final_lactate.*,V_urine_output.value_sum "urine_output_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_urine_output
    ON V_urine_output.subject_id = T_final_lactate.subject_id
    WHERE V_urine_output.charttime = T_final_lactate.J3
;

---------------------------------Jointures--------------------------

CREATE OR REPLACE VIEW urine_output_B0 AS 
    SELECT T_final_lactate.*, urine_output_0."urine_output_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN urine_output_0
    ON urine_output_0.subject_id = T_final_lactate.subject_id
;
CREATE OR REPLACE VIEW urine_output_B1 AS
    SELECT urine_output_B0.*, urine_output_1."urine_output_J1(mL)"
    FROM urine_output_B0
    LEFT JOIN urine_output_1
    ON urine_output_1.subject_id = urine_output_B0.subject_id
;
CREATE OR REPLACE VIEW urine_output_B2 AS
    SELECT urine_output_B1.*, urine_output_2."urine_output_J2(mL)"
    FROM urine_output_B1
    LEFT JOIN urine_output_2
    ON urine_output_2.subject_id = urine_output_B1.subject_id
;
CREATE OR REPLACE VIEW urine_output_B3 AS
    SELECT urine_output_B2.*, urine_output_3."urine_output_J3(mL)"
    FROM urine_output_B2
    LEFT JOIN urine_output_3
    ON urine_output_3.subject_id = urine_output_B2.subject_id
;

CREATE TABLE T_final_urine AS 
    SELECT T_final_PaO2_FiO2.*
	,urine_output_B3."urine_output_J0(mL)"
	,urine_output_B3."urine_output_J1(mL)"
    ,urine_output_B3."urine_output_J2(mL)"
    ,urine_output_B3."urine_output_J3(mL)"
    FROM T_final_PaO2_FiO2
    LEFT JOIN urine_output_B3
    ON T_final_PaO2_FiO2.subject_id = urine_output_B3.subject_id and  T_final_PaO2_FiO2.hadm_id = urine_output_B3.hadm_id
;

----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*entrées*/
----------------------------------------------------------------------------------------------------------------------------------------
/* Les variables "entrees_J0(mL)","entrees_J1(mL)","entrees_J2(mL)" et "entrees_J3(mL)" sont créees suivant le même principe
que les variables "ultrafiltration_J1(mL)","ultrafiltration_J2(mL)","ultrafiltration_J3(mL)" et "ultrafiltration_J0(mL)" à la seule difference
que pour les variables d'ultrafiltration, nous recherchions juste l'itemid correspondant à 'ultrafiltration' alors que pour les entrées, nous
recherchons un ensemble d'itemid:
     228341 : NaCl 23.4%
    ,225161 : NaCl 3% (Hypertonic Saline)
    ,225828 : LR
    ,225165 : Bicarbonate Base
    ,227533 : Sodium Bicarbonate 8.4% (Amp)
    ,226377 : PACU PO Intake
    ,225827 : D5LR
    ,225159 : NaCl 0.45%
    ,225158 : NaCl 0.9%
    ,226375 : PACU Crystalloid Intake
    */

CREATE OR REPLACE VIEW V_mesureentrees AS
    SELECT*
    FROM mimiciv_icu.inputevents inputs
    WHERE inputs.itemid in (228341,225161,225828,225165,227533,226377,225827,225159,225158,226375)
;


CREATE OR REPLACE VIEW V_entrees_final AS
    SELECT sum(V_mesureentrees.amount) sum_entrees,
            V_mesureentrees.subject_id,
            date(V_mesureentrees.starttime) starttime
    FROM V_mesureentrees
    GROUP BY V_mesureentrees.subject_id, date(V_mesureentrees.starttime)
;


CREATE OR REPLACE VIEW entrees_0 AS 
SELECT T_final_lactate.*
,V_entrees_final.sum_entrees AS "entrees_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN V_entrees_final
    ON V_entrees_final.subject_id = T_final_lactate.subject_id
    WHERE V_entrees_final.starttime = T_final_lactate.J0
;


CREATE OR REPLACE VIEW entrees_1 AS 
SELECT T_final_lactate.*
,V_entrees_final.sum_entrees AS "entrees_J1(mL)"
    FROM T_final_lactate
    LEFT JOIN V_entrees_final
    ON V_entrees_final.subject_id = T_final_lactate.subject_id
    WHERE V_entrees_final.starttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW entrees_2 AS 
SELECT T_final_lactate.*
,V_entrees_final.sum_entrees AS "entrees_J2(mL)"
    FROM T_final_lactate
    LEFT JOIN V_entrees_final
    ON V_entrees_final.subject_id = T_final_lactate.subject_id
    WHERE V_entrees_final.starttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW entrees_3 AS 
SELECT T_final_lactate.*
,V_entrees_final.sum_entrees AS "entrees_J3(mL)"
    FROM T_final_lactate
    LEFT JOIN V_entrees_final
    ON V_entrees_final.subject_id = T_final_lactate.subject_id
    WHERE V_entrees_final.starttime = T_final_lactate.J3
;

CREATE OR REPLACE VIEW entrees_B0 AS 
    SELECT T_final_lactate.*, entrees_0."entrees_J0(mL)"
    FROM T_final_lactate
    LEFT JOIN entrees_0
    ON entrees_0.subject_id = T_final_lactate.subject_id
;
CREATE OR REPLACE VIEW entrees_B1 AS 
    SELECT entrees_B0.*, entrees_1."entrees_J1(mL)"
    FROM entrees_B0
    LEFT JOIN entrees_1
    ON entrees_1.subject_id = entrees_B0.subject_id
;

CREATE OR REPLACE VIEW entrees_B2 AS 
    SELECT entrees_B1.*, entrees_2."entrees_J2(mL)"
    FROM entrees_B1
    LEFT JOIN entrees_2
    ON entrees_2.subject_id = entrees_B1.subject_id
;

CREATE OR REPLACE VIEW entrees_B3 AS 
    SELECT entrees_B2.*, entrees_3."entrees_J3(mL)"
    FROM entrees_B2
    LEFT JOIN entrees_3
    ON entrees_3.subject_id = entrees_B2.subject_id
;

CREATE TABLE T_final_entrees AS 
    SELECT T_final_urine.*
    ,entrees_B3."entrees_J0(mL)"
    ,entrees_B3."entrees_J1(mL)"
    ,entrees_B3."entrees_J2(mL)"
    ,entrees_B3."entrees_J3(mL)"
    FROM T_final_urine 
    LEFT JOIN entrees_B3
    ON T_final_urine.subject_id = entrees_B3.subject_id
;   


----------------------------------------------------------------------------------------------------------------------------------------
                                                            /*bilan entrées/sorties*/
----------------------------------------------------------------------------------------------------------------------------------------
/*Dans cette partie, nous créons les variables qui renseignent les bilans entrées-sorties. En effet, 
Pour le bilan entrées-sorties, nous allons dans un premier temps sommer toutes les entrées dans la variable 'total_entrees'dans un premier 
temps et dans un second temps toutes les sorties dans la variable 'total_sorties'. Les entrées sont constituées de la variable entrees 
crées ci-haut et des variables platelets et FF_plasmas. Les sorties sont composées des variables hemodialyse, urine_output,PACU_urine,
OR_urine et ultrafiltration. Toutes ces variables sont en ml.
Si pour un individu, toutes les entrées et toutes les sorties sont null, le bilan sera nulle et cet individu sera retiré de l'étude.
*/ 
CREATE TABLE T_final_base_travail AS 
    SELECT T_final_entrees.*
    ,(CASE 
    WHEN
    (T_final_entrees."entrees_J0(mL)" is null and T_final_entrees."FF_plasmas_J0(mL)" is null and
    T_final_entrees."platelets_J0(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."entrees_J0(mL)",0)+COALESCE(T_final_entrees."FF_plasmas_J0(mL)",0)+
    COALESCE(T_final_entrees."platelets_J0(mL)",0)) 
    END) AS total_entree_J0

    ,(CASE 
    WHEN
    (T_final_entrees."urine_output_J0(mL)" is null  and
    T_final_entrees."PACU_urine_J0(mL)" is null and T_final_entrees."OR_urine_J0(mL)"is null 
	and T_final_entrees."ultrafiltration_J0(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."urine_output_J0(mL)",0)
    +COALESCE(T_final_entrees."PACU_urine_J0(mL)",0)+COALESCE(T_final_entrees."OR_urine_J0(mL)",0)
		 +COALESCE(T_final_entrees."ultrafiltration_J0(mL)",0)) 
    END) AS total_sortie_J0

    ,(CASE 
    WHEN
    (T_final_entrees."entrees_J1(mL)" is null and T_final_entrees."FF_plasmas_J1(mL)" is null and
    T_final_entrees."platelets_J1(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."entrees_J1(mL)",0)+COALESCE(T_final_entrees."FF_plasmas_J1(mL)",0)+
    COALESCE(T_final_entrees."platelets_J1(mL)",0)) 
    END) AS total_entree_J1

    ,(CASE 
    WHEN
    (T_final_entrees."urine_output_J1(mL)" is null  and
    T_final_entrees."PACU_urine_J1(mL)" is null and T_final_entrees."OR_urine_J1(mL)"is null 
	and T_final_entrees."ultrafiltration_J1(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."urine_output_J1(mL)",0)
    +COALESCE(T_final_entrees."PACU_urine_J1(mL)",0)+COALESCE(T_final_entrees."OR_urine_J1(mL)",0)
		 +COALESCE(T_final_entrees."ultrafiltration_J1(mL)",0)) 
    END) AS total_sortie_J1

    ,(CASE 
    WHEN
    (T_final_entrees."entrees_J2(mL)" is null and T_final_entrees."FF_plasmas_J2(mL)" is null and
    T_final_entrees."platelets_J2(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."entrees_J2(mL)",0)+COALESCE(T_final_entrees."FF_plasmas_J2(mL)",0)+
    COALESCE(T_final_entrees."platelets_J2(mL)",0)) 
    END) AS total_entree_J2

    ,(CASE 
    WHEN
    (T_final_entrees."urine_output_J2(mL)" is null  and
    T_final_entrees."PACU_urine_J2(mL)" is null and T_final_entrees."OR_urine_J2(mL)"is null 
	and T_final_entrees."ultrafiltration_J2(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."urine_output_J2(mL)",0)
    +COALESCE(T_final_entrees."PACU_urine_J2(mL)",0)+COALESCE(T_final_entrees."OR_urine_J2(mL)",0)
		 +COALESCE(T_final_entrees."ultrafiltration_J2(mL)",0)) 
    END) AS total_sortie_J2

    ,(CASE 
    WHEN
    (T_final_entrees."entrees_J3(mL)" is null and T_final_entrees."FF_plasmas_J3(mL)" is null and
    T_final_entrees."platelets_J3(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."entrees_J3(mL)",0)+COALESCE(T_final_entrees."FF_plasmas_J3(mL)",0)+
    COALESCE(T_final_entrees."platelets_J3(mL)",0)) 
    END) AS total_entree_J3

    ,(CASE 
    WHEN
    (T_final_entrees."urine_output_J3(mL)" is null  and
    T_final_entrees."PACU_urine_J3(mL)" is null and T_final_entrees."OR_urine_J3(mL)"is null 
	and T_final_entrees."ultrafiltration_J3(mL)" is null) THEN NULL
    ELSE 
    (COALESCE(T_final_entrees."urine_output_J3(mL)",0)
    +COALESCE(T_final_entrees."PACU_urine_J3(mL)",0)+COALESCE(T_final_entrees."OR_urine_J3(mL)",0)
		 +COALESCE(T_final_entrees."ultrafiltration_J3(mL)",0)) 
    END) AS total_sortie_J3
    
 
FROM  T_final_entrees;


CREATE TABLE T_utile_travail AS
    SELECT T_final_base_travail.*
    ,(CASE 
    WHEN(T_final_base_travail.total_entree_J0 is null and T_final_base_travail.total_sortie_J0 is null) THEN NULL
    ELSE(COALESCE(T_final_base_travail.total_entree_J0,0)-COALESCE(T_final_base_travail.total_sortie_J0,0)) 
    END)
    AS bilan_entre_sortie_J0

     ,(CASE 
    WHEN(T_final_base_travail.total_entree_J1 is null and T_final_base_travail.total_sortie_J1 is null) THEN NULL
    ELSE(COALESCE(T_final_base_travail.total_entree_J1,0)-COALESCE(T_final_base_travail.total_sortie_J1,0)) 
    END)
    AS bilan_entre_sortie_J1

     ,(CASE 
    WHEN(T_final_base_travail.total_entree_J2 is null and T_final_base_travail.total_sortie_J2 is null) THEN NULL
    ELSE(COALESCE(T_final_base_travail.total_entree_J2,0)-COALESCE(T_final_base_travail.total_sortie_J2,0)) 
    END)
    AS bilan_entre_sortie_J2

    ,(CASE 
    WHEN(T_final_base_travail.total_entree_J3 is null and T_final_base_travail.total_sortie_J3 is null) THEN NULL
    ELSE(COALESCE(T_final_base_travail.total_entree_J3,0)-COALESCE(T_final_base_travail.total_sortie_J3,0)) 
    END)
    AS bilan_entre_sortie_J3
   
FROM T_final_base_travail;

select* from T_utile_travail;

CREATE TABLE data_finale as
select* from T_utile_travail 
Where 
T_utile_travail.bilan_entre_sortie_J0 is not null or 
T_utile_travail.bilan_entre_sortie_J1 is not null or 
T_utile_travail.bilan_entre_sortie_J2 is not null or 
T_utile_travail.bilan_entre_sortie_J3 is not null;

select* from data_finale;


---------------------------------------------------------------------------------------------------------------------
                        /* Catecholamine*/
-----------------------------------------------------------------------------------------------------------------------
/*Après avoir obtenu les quantités de catécholamines des patients, nous avons calculé un score nommé VIS pour J0,J1,J2 et J3.La fonction
COALESCE replace une valeur 'Null' par 0. */
CREATE TABLE AS T_data
SELECT data_finale.*
    ,(100*COALESCE(data_finale."epinephrine_J0(mcg/Kg/min)",0)+
    100*COALESCE(data_finale."norepinephrine_J0(mcg/Kg/min)",0)+
    10*COALESCE(data_finale."phenylephrine_J0(mcg/Kg/min)",0)+
    COALESCE(data_finale."dopamine_J0(mcg/Kg/min)",0)+
    COALESCE(data_finale."dobutamine_J0(mcg/Kg/min)",0)) AS VIS_J0

  ,(100*COALESCE(data_finale."epinephrine_J1(mcg/Kg/min)",0)+
    100*COALESCE(data_finale."norepinephrine_J1(mcg/Kg/min)",0)+
    10*COALESCE(data_finale."phenylephrine_J1(mcg/Kg/min)",0)+
    COALESCE(data_finale."dopamine_J1(mcg/Kg/min)",0)+
    COALESCE(data_finale."dobutamine_J1(mcg/Kg/min)",0)) AS VIS_J1

    ,(100*COALESCE(data_finale."epinephrine_J2(mcg/Kg/min)",0)+
    100*COALESCE(data_finale."norepinephrine_J2(mcg/Kg/min)",0)+
    10*COALESCE(data_finale."phenylephrine_J2(mcg/Kg/min)",0)+
    COALESCE(data_finale."dopamine_J2(mcg/Kg/min)",0)+
    COALESCE(data_finale."dobutamine_J2(mcg/Kg/min)",0)) AS VIS_J2

    ,(100*COALESCE(data_finale."epinephrine_J3(mcg/Kg/min)",0)+
    100*COALESCE(data_finale."norepinephrine_J3(mcg/Kg/min)",0)+
    10*COALESCE(data_finale."phenylephrine_J3(mcg/Kg/min)",0)+
    COALESCE(data_finale."dopamine_J3(mcg/Kg/min)",0)+
    COALESCE(data_finale."dobutamine_J3(mcg/Kg/min)",0)) AS VIS_J3
FROM data_finale;
	
---------------------------------------------------------------------------------------------------------------------------------
                                            /* 227428 SOFA Score chartevents*/
---------------------------------------------------------------------------------------------------------------------------------
--les variables "score_SOFA_J0","score_SOFA_J1","score_SOFA_J2" et "score_SOFA_J3" sont créees selon le même principe que les variables
-- ph crées plus haut.
CREATE OR REPLACE VIEW V_mesurescore_SOFA AS
    SELECT *
    FROM mimiciv_icu.chartevents char
    WHERE char.itemid = 227428; 

CREATE OR REPLACE VIEW V_score_SOFA AS
    SELECT AVG(V_mesurescore_SOFA.valuenum) value_moyen
    ,V_mesurescore_SOFA.subject_id,date(V_mesurescore_SOFA.charttime) charttime
    FROM V_mesurescore_SOFA
    GROUP BY V_mesurescore_SOFA.subject_id, date(V_mesurescore_SOFA.charttime)
;

CREATE OR REPLACE VIEW score_SOFA_0 AS 
SELECT T_final_lactate.*,V_score_SOFA.value_moyen "score_SOFA_J0"
    FROM T_final_lactate
    LEFT JOIN V_score_SOFA
    ON V_score_SOFA.subject_id = T_final_lactate.subject_id
    WHERE V_score_SOFA.charttime = T_final_lactate.J0
;

CREATE OR REPLACE VIEW score_SOFA_1 AS 
SELECT T_final_lactate.*,V_score_SOFA.value_moyen "score_SOFA_J1"
    FROM T_final_lactate
    LEFT JOIN V_score_SOFA
    ON V_score_SOFA.subject_id = T_final_lactate.subject_id
    WHERE V_score_SOFA.charttime = T_final_lactate.J1
;

CREATE OR REPLACE VIEW score_SOFA_2 AS 
SELECT T_final_lactate.*,V_score_SOFA.value_moyen "score_SOFA_J2"
    FROM T_final_lactate
    LEFT JOIN V_score_SOFA
    ON V_score_SOFA.subject_id = T_final_lactate.subject_id
    WHERE V_score_SOFA.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW score_SOFA_3 AS 
SELECT T_final_lactate.*,V_score_SOFA.value_moyen "score_SOFA_J3"
    FROM T_final_lactate
    LEFT JOIN V_score_SOFA
    ON V_score_SOFA.subject_id = T_final_lactate.subject_id
    WHERE V_score_SOFA.charttime = T_final_lactate.J3
;

------------------
CREATE OR REPLACE VIEW score_SOFA_B0 AS 
    SELECT T_final_lactate.*, score_SOFA_0."score_SOFA_J0"
    FROM T_final_lactate
    LEFT JOIN score_SOFA_0
    ON score_SOFA_0.subject_id = T_final_lactate.subject_id
;

CREATE OR REPLACE VIEW score_SOFA_B1 AS
    SELECT score_SOFA_B0.*, score_SOFA_1."score_SOFA_J1"
    FROM score_SOFA_B0
    LEFT JOIN score_SOFA_1
    ON score_SOFA_1.subject_id = score_SOFA_B0.subject_id
;

CREATE OR REPLACE VIEW score_SOFA_B2 AS
    SELECT score_SOFA_B1.*, score_SOFA_2."score_SOFA_J2"
    FROM score_SOFA_B1
    LEFT JOIN score_SOFA_2
    ON score_SOFA_2.subject_id = score_SOFA_B1.subject_id
;

CREATE OR REPLACE VIEW score_SOFA_B3 AS
    SELECT score_SOFA_B2.*, score_SOFA_3."score_SOFA_J3"
    FROM score_SOFA_B2
    LEFT JOIN score_SOFA_3
    ON score_SOFA_3.subject_id = score_SOFA_B2.subject_id
;

CREATE TABLE T_final_score_SOFA AS 
    SELECT T_data.*
    ,score_SOFA_B3."score_SOFA_J0"
    ,score_SOFA_B3."score_SOFA_J1"
    ,score_SOFA_B3."score_SOFA_J2"
    ,score_SOFA_B3."score_SOFA_J3"
    FROM T_data 
    LEFT JOIN score_SOFA_B3
    ON T_data.subject_id = score_SOFA_B3.subject_id
;   
-------------------------------------------------------------------------------------------------------------------------------
                                               /*226260 Mechanically Ventilated*/
-------------------------------------------------------------------------------------------------------------------------------
-- Dans la table chartevents, l'itemid renseignant sur la ventilation mécanique est une variable binaire, donc elle prend la valeur
--1 si l'individu a été ventilé méchaniquement et 0 sinon

-- Nous créons la vue 'V_mesureventilation_mechanique' issue de la table 'chartevents' pour récupérer toutes les lignes qui à la 
-- ventillation méchanique
CREATE OR REPLACE VIEW V_mesureventilation_mechanique AS
    SELECT *
    FROM mimiciv_icu.chartevents char
    WHERE char.itemid = 226260; 


-- Dans la vue, 'V_mesureventilation_mechanique' nous avons plusieurs enregistrements à differents instants d'une journée pour un même
--patient. Ainsi, pour résumer l'information d'une journée pour un patient, nous prenons la valeur maximale. Si elle est egale à 1
-- cela signifiera qu'à un moment donnée de la journée, l'individu a été ventillé méchaniquement.

CREATE OR REPLACE VIEW V_ventilation_mechanique AS
    SELECT max(V_mesureventilation_mechanique.valuenum) value_max
    ,V_mesureventilation_mechanique.subject_id,date(V_mesureventilation_mechanique.charttime) charttime
    FROM V_mesureventilation_mechanique
    GROUP BY V_mesureventilation_mechanique.subject_id, date(V_mesureventilation_mechanique.charttime)
;

-- Ensuite, nous effectuons une jointure lorque la journée pendant laquelle l'individu a été ventillé méchaniquement correspond au J0 de 
--l'individu. Et nous stockons la valeur maximale de la variable 'ventilation_mechanique' dans la variable "ventilation_mechanique_J0"

CREATE OR REPLACE VIEW ventilation_mechanique_0 AS 
SELECT T_final_lactate.*,V_ventilation_mechanique.value_max "ventilation_mechanique_J0"
    FROM T_final_lactate
    LEFT JOIN V_ventilation_mechanique
    ON V_ventilation_mechanique.subject_id = T_final_lactate.subject_id
    WHERE V_ventilation_mechanique.charttime = T_final_lactate.J0
;

--De même, nous effectuons une jointure, lorsque la date de la ventillation méchanique coincide avec le J1 des patients. 
--Et l'information est réceuillie dans la variable "ventilation_mechanique_J1"
CREATE OR REPLACE VIEW ventilation_mechanique_1 AS 
SELECT T_final_lactate.*,V_ventilation_mechanique.value_max "ventilation_mechanique_J1"
    FROM T_final_lactate
    LEFT JOIN V_ventilation_mechanique
    ON V_ventilation_mechanique.subject_id = T_final_lactate.subject_id
    WHERE V_ventilation_mechanique.charttime = T_final_lactate.J1
;

-- Nous faisons de même pour la variable "ventilation_mechanique_J2" et "ventilation_mechanique_J3"
CREATE OR REPLACE VIEW ventilation_mechanique_2 AS 
SELECT T_final_lactate.*,V_ventilation_mechanique.value_max "ventilation_mechanique_J2"
    FROM T_final_lactate
    LEFT JOIN V_ventilation_mechanique
    ON V_ventilation_mechanique.subject_id = T_final_lactate.subject_id
    WHERE V_ventilation_mechanique.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW ventilation_mechanique_3 AS 
SELECT T_final_lactate.*,V_ventilation_mechanique.value_max "ventilation_mechanique_J3"
    FROM T_final_lactate
    LEFT JOIN V_ventilation_mechanique
    ON V_ventilation_mechanique.subject_id = T_final_lactate.subject_id
    WHERE V_ventilation_mechanique.charttime = T_final_lactate.J3
;

--Ensuite, nous effectuons une jointure gauche entre les patients ayant eu l'arrêt cardiaque et une mesure de lactate supérieure à 2
-- et les patients ayant été ventillés méchaniquement le jour de leur arrêt cardiaque. Et on attribuera la valeur 'NULL' à 
-- la variable 'ventilation_mechanique_J0' pour ceux dont la variable n'a pas été renseignée.

CREATE OR REPLACE VIEW ventilation_mechanique_B0 AS 
    SELECT T_final_lactate.*, ventilation_mechanique_0."ventilation_mechanique_J0"
    FROM T_final_lactate
    LEFT JOIN ventilation_mechanique_0
    ON ventilation_mechanique_0.subject_id = T_final_lactate.subject_id
;


-- De même, nous effectuons une jointure la vue 'ventilation_mechanique_B0' et la vue 'ventilation_mechanique_1' pour ajouter aux variables de la vue
--'ventilation_mechanique_B0', la variable "ventilation_mechanique_J1" de la vue 'ventilation_mechanique_1'.Le traitement de cette variable est le même 
-- que celui des variables "ventilation_mechanique_0".

CREATE OR REPLACE VIEW ventilation_mechanique_B1 AS
    SELECT ventilation_mechanique_B0.*, ventilation_mechanique_1."ventilation_mechanique_J1"
    FROM ventilation_mechanique_B0
    LEFT JOIN ventilation_mechanique_1
    ON ventilation_mechanique_1.subject_id = ventilation_mechanique_B0.subject_id
;
--Nous faisons de même pour les etendre les variables "ventilation_mechanique_J2" et "ventilation_mechanique_J3" à tous les patients qui se 
--trouvent dans la table 'T_finale_lactate'
CREATE OR REPLACE VIEW ventilation_mechanique_B2 AS
    SELECT ventilation_mechanique_B1.*, ventilation_mechanique_2."ventilation_mechanique_J2"
    FROM ventilation_mechanique_B1
    LEFT JOIN ventilation_mechanique_2
    ON ventilation_mechanique_2.subject_id = ventilation_mechanique_B1.subject_id
;

CREATE OR REPLACE VIEW ventilation_mechanique_B3 AS
    SELECT ventilation_mechanique_B2.*, ventilation_mechanique_3."ventilation_mechanique_J3"
    FROM ventilation_mechanique_B2
    LEFT JOIN ventilation_mechanique_3
    ON ventilation_mechanique_3.subject_id = ventilation_mechanique_B2.subject_id
;

--
--Pour finir, nous effectuons une jointure entre la vue 'dialysis_patient_B3' et la table 'T_final_score_SOFA' obtenue après 
--création des variables.Cette jointure a pour but de completer la table 'T_final_score_SOFA' avec 
-- les variables "ventilation_mechanique_J0","ventilation_mechanique_J1","ventilation_mechanique_J2" et "ventilation_mechanique_J2"

CREATE TABLE T_final_ventilation_mechanique AS 
    SELECT T_final_score_SOFA.*
    ,ventilation_mechanique_B3."ventilation_mechanique_J0"
    ,ventilation_mechanique_B3."ventilation_mechanique_J1"
    ,ventilation_mechanique_B3."ventilation_mechanique_J2"
    ,ventilation_mechanique_B3."ventilation_mechanique_J3"
    FROM T_final_score_SOFA 
    LEFT JOIN ventilation_mechanique_B3
    ON T_final_score_SOFA.subject_id = ventilation_mechanique_B3.subject_id
;   


-------------------------------------------------------------------------------------------------------------------------------
                                               /*225126 Dialysis patient*/
-------------------------------------------------------------------------------------------------------------------------------
-- Dans la table 'chartevents', la valeur itemid 225126 correspond à la variable 'dialysis_patient'. C'est une variable binaire
-- qui prend la valeur 1 si l'individu est dialysé et 0 sinon. Donc, dans cette section, nous récupérons cette variable de sorte
-- que si l'individu est dialysé, la variable que nous allons créer prenne 1 et 0 s'il n'a pas été dialysé. Cependant, si la 
--variable 'dialysis_patient' n'est pas renseignée pour certains individus, la variable que nous allons créée prendra la valeur
-- 'null'.

-- Nous créons la vue 'V_mesuredialysis_patient' issue de la table 'chartevents' pour récupérer toutes les lignes qui correspondent
-- à la variable 'dialysis_patient'
CREATE OR REPLACE VIEW V_mesuredialysis_patient AS
    SELECT *
    FROM mimiciv_icu.chartevents char
    WHERE char.itemid = 225126; 

-- Dans la vue, 'V_mesuredialysis_patient' nous avons plusieurs enregistrements à differents instants d'une journée pour un même
--patient. Ainsi, pour résumer l'information d'une journée pour un patient, nous prenons la valeur maximale. Si elle est egale à 1
-- cela signifiera qu'à un moment donnée de la journée, l'individu a été dialysé.
CREATE OR REPLACE VIEW V_dialysis_patient AS
    SELECT max(V_mesuredialysis_patient.valuenum) value_max
    ,V_mesuredialysis_patient.subject_id,date(V_mesuredialysis_patient.charttime) charttime
    FROM V_mesuredialysis_patient
    GROUP BY V_mesuredialysis_patient.subject_id, date(V_mesuredialysis_patient.charttime)
;

-- Ensuite, nous effectuons une jointure lorque la journée d'administration correspond au J0 de l'individu. Et nous stockons la valeur
--maximale de la variable 'dialysis_patient' dans la variable "dialysis_patient_J0"
CREATE OR REPLACE VIEW dialysis_patient_0 AS 
SELECT T_final_lactate.*,V_dialysis_patient.value_max "dialysis_patient_J0"
    FROM T_final_lactate
    LEFT JOIN V_dialysis_patient
    ON V_dialysis_patient.subject_id = T_final_lactate.subject_id
    WHERE V_dialysis_patient.charttime = T_final_lactate.J0
;

--De même, nous effectuons une jointure, lorsque la date de la dialyse coincide avec le J1 des patients. Et l'information est réceuillie 
-- dans la variable "dialysis_patient_J1"
CREATE OR REPLACE VIEW dialysis_patient_1 AS 
SELECT T_final_lactate.*,V_dialysis_patient.value_max "dialysis_patient_J1"
    FROM T_final_lactate
    LEFT JOIN V_dialysis_patient
    ON V_dialysis_patient.subject_id = T_final_lactate.subject_id
    WHERE V_dialysis_patient.charttime = T_final_lactate.J1
;

-- Nous faisons de même pour la variable "dialysis_patient_J2" et "dialysis_patient_J3"
CREATE OR REPLACE VIEW dialysis_patient_2 AS 
SELECT T_final_lactate.*,V_dialysis_patient.value_max "dialysis_patient_J2"
    FROM T_final_lactate
    LEFT JOIN V_dialysis_patient
    ON V_dialysis_patient.subject_id = T_final_lactate.subject_id
    WHERE V_dialysis_patient.charttime = T_final_lactate.J2
;

CREATE OR REPLACE VIEW dialysis_patient_3 AS 
SELECT T_final_lactate.*,V_dialysis_patient.value_max "dialysis_patient_J3"
    FROM T_final_lactate
    LEFT JOIN V_dialysis_patient
    ON V_dialysis_patient.subject_id = T_final_lactate.subject_id
    WHERE V_dialysis_patient.charttime = T_final_lactate.J3
;

------------------
--Ensuite, nous effectuons une jointure gauche entre les patients ayant eu l'arrêt cardiaque et une mesure de lactate supérieure à 2
-- et les patients ayant vu la variable 'dialysis_patient' renseignée le jour de leur arrêt cardiaque(J0).Ceux qui n'auront pas 
--la variable 'dialysis_patient' renseignée à J0, auront la valeur 'NULL' pour la variable 'dialysis_patient'

CREATE OR REPLACE VIEW dialysis_patient_B0 AS 
    SELECT T_final_lactate.*, dialysis_patient_0."dialysis_patient_J0"
    FROM T_final_lactate
    LEFT JOIN dialysis_patient_0
    ON dialysis_patient_0.subject_id = T_final_lactate.subject_id
;

--Ensuite, nous effectuons une jointure entre la vue précédement obtenue et la vue 'dialysis_patient_1' pour récupérer la variable "dialysis_patient_J1"
--Ainsi, les patients pour lesquels "dialysis_patient_J1" existe garderont leur valeur mais ceux qui n'en ont pas, auront la valeur 'NULL'.
CREATE OR REPLACE VIEW dialysis_patient_B1 AS
    SELECT dialysis_patient_B0.*, dialysis_patient_1."dialysis_patient_J1"
    FROM dialysis_patient_B0
    LEFT JOIN dialysis_patient_1
    ON dialysis_patient_1.subject_id = dialysis_patient_B0.subject_id
;

-- De même, nous effectuons une jointure la vue 'dialysis_patient_B1' et la vue 'dialysis_patient_2' pour ajouter aux variables de la vue
--'dialysis_patient_B1', la variable "dialysis_patient_J2" de la vue 'dialysis_patient_2'.Le traitement de cette variable est le même 
-- que celui des variables "dialysis_patient_J1" et "dialysis_patient_J0"
CREATE OR REPLACE VIEW dialysis_patient_B2 AS
    SELECT dialysis_patient_B1.*, dialysis_patient_2."dialysis_patient_J2"
    FROM dialysis_patient_B1
    LEFT JOIN dialysis_patient_2
    ON dialysis_patient_2.subject_id = dialysis_patient_B1.subject_id
;

-- De même, nous construisons la variable "dialysis_patient_J3" en joignant 'dialysis_patient_3' et 'dialysis_patient_B2'. Après cette jointure,
-- nous avons pour tous les individus présents dans la table 'T_finale_lactate' les variables "dialysis_patient_J3","dialysis_patient_J2",
--"dialysis_patient_J0" et "dialysis_patient_J1"
CREATE OR REPLACE VIEW dialysis_patient_B3 AS
    SELECT dialysis_patient_B2.*, dialysis_patient_3."dialysis_patient_J3"
    FROM dialysis_patient_B2
    LEFT JOIN dialysis_patient_3
    ON dialysis_patient_3.subject_id = dialysis_patient_B2.subject_id
;

--Pour finir, nous effectuons une jointure entre la vue 'dialysis_patient_B3' et la table 'T_final_ventilation_mechanique' obtenue après 
--création des indicatrices de ventilation mécanique.Cette jointure a pour but de completer la table 'T_final_ventilation_mechanique' avec 
-- les variables "dialysis_patient_J3","dialysis_patient_J2", "dialysis_patient_J0" et "dialysis_patient_J1"
CREATE TABLE T_final_dialysis_patient AS 
    SELECT T_final_ventilation_mechanique.*
    ,dialysis_patient_B3."dialysis_patient_J0"
    ,dialysis_patient_B3."dialysis_patient_J1"
    ,dialysis_patient_B3."dialysis_patient_J2"
    ,dialysis_patient_B3."dialysis_patient_J3"
    FROM T_final_ventilation_mechanique 
    LEFT JOIN dialysis_patient_B3
    ON T_final_ventilation_mechanique.subject_id = dialysis_patient_B3.subject_id
;   


-----------------------------------------------------------------------------------------------------------------------
                                            /*Creation de la table finale*/
-----------------------------------------------------------------------------------------------------------------------
--Création de la table finale sur laquelle, les analyses doivent se faire. On séléctionne les variables suivantes.
CREATE TABLE T_mimic_final AS
    SELECT 
    T_final_dialysis_patient.subject_id
    ,T_final_dialysis_patient.hadm_id
    ,T_final_dialysis_patient.gender
    ,T_final_dialysis_patient.anchor_age
    ,T_final_dialysis_patient.datedebut
    ,T_final_dialysis_patient.anchor_year
    ,T_final_dialysis_patient.anchor_year_group

    ,T_final_dialysis_patient.J0
    ,T_final_dialysis_patient.J1
    ,T_final_dialysis_patient.J2
    ,T_final_dialysis_patient.J3

    ,T_final_dialysis_patient.VIS_J0
    ,T_final_dialysis_patient.VIS_J1
    ,T_final_dialysis_patient.VIS_J2
    ,T_final_dialysis_patient.VIS_J3

    ,T_final_dialysis_patient."score_SOFA_J0"
    ,T_final_dialysis_patient."score_SOFA_J1"
    ,T_final_dialysis_patient."score_SOFA_J2"
    ,T_final_dialysis_patient."score_SOFA_J3"

    ,T_final_dialysis_patient."ventilation_mechanique_J0"
    ,T_final_dialysis_patient."ventilation_mechanique_J1"
    ,T_final_dialysis_patient."ventilation_mechanique_J2"
    ,T_final_dialysis_patient."ventilation_mechanique_J3"

    ,T_final_dialysis_patient."dialysis_patient_J0"
    ,T_final_dialysis_patient."dialysis_patient_J1"
    ,T_final_dialysis_patient."dialysis_patient_J2"
    ,T_final_dialysis_patient."dialysis_patient_J3"

    ,T_final_dialysis_patient.total_entree_J0
    ,T_final_dialysis_patient.total_sortie_J0
    ,T_final_dialysis_patient.bilan_entre_sortie_J0

    ,T_final_dialysis_patient.total_entree_J1
    ,T_final_dialysis_patient.total_sortie_J1
    ,T_final_dialysis_patient.bilan_entre_sortie_J1

    ,T_final_dialysis_patient.total_entree_J2
    ,T_final_dialysis_patient.total_sortie_J2
    ,T_final_dialysis_patient.bilan_entre_sortie_J2

    ,T_final_dialysis_patient.total_entree_J3
    ,T_final_dialysis_patient.total_sortie_J3
    ,T_final_dialysis_patient.bilan_entre_sortie_J3
  
    ,T_final_dialysis_patient."PaO2_FiO2_max_J3"
	,T_final_dialysis_patient."PaO2_FiO2_max_J2"
	,T_final_dialysis_patient."PaO2_FiO2_max_J1"
	,T_final_dialysis_patient."PaO2_FiO2_max_J0"

	,T_final_dialysis_patient."PaO2_FiO2_min_J3"
	,T_final_dialysis_patient."PaO2_FiO2_min_J2"
	,T_final_dialysis_patient."PaO2_FiO2_min_J1"
	,T_final_dialysis_patient."PaO2_FiO2_min_J0" 

    ,T_final_dialysis_patient.heart_failure
    ,T_final_dialysis_patient.obesity
    ,T_final_dialysis_patient.chronic_pulmonary_disease
    ,T_final_dialysis_patient.liver_disease
    ,T_final_dialysis_patient.diabetes
    ,T_final_dialysis_patient.renal_disease
    ,T_final_dialysis_patient.malignant_cancer
    ,T_final_dialysis_patient.aids 
    

    ,T_final_dialysis_patient."thermodilutionCO_max_J3(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_max_J2(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_max_J1(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_max_J0(L/min)"

	,T_final_dialysis_patient."thermodilutionCO_min_J3(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_min_J2(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_min_J1(L/min)"
	,T_final_dialysis_patient."thermodilutionCO_min_J0(L/min)"

    ,T_final_dialysis_patient."albumin_J0(g/dL)"
    ,T_final_dialysis_patient."albumin_J1(g/dL)"
    ,T_final_dialysis_patient."albumin_J2(g/dL)"
    ,T_final_dialysis_patient."albumin_J3(g/dL)"

    ,T_final_dialysis_patient."index_cardiac_min_J0(L/min/m2)"
    ,T_final_dialysis_patient."index_cardiac_moyen_J0(L/min/m2)"

    ,T_final_dialysis_patient.deces_date
	,T_final_dialysis_patient.indicatrice_deces_J0
	,T_final_dialysis_patient.indicatrice_deces_J1
	,T_final_dialysis_patient.indicatrice_deces_J2
	,T_final_dialysis_patient.indicatrice_deces_J3
	,T_final_dialysis_patient.indicatrice_deces_J14
	,T_final_dialysis_patient.indicatrice_deces_J30

    ,T_final_dialysis_patient.indicatrice_temperature_J0
    ,T_final_dialysis_patient.indicatrice_temperature_J1
    ,T_final_dialysis_patient.indicatrice_temperature_J2
    ,T_final_dialysis_patient.indicatrice_temperature_J3

    ,T_final_dialysis_patient.indicatrice_glycemie_J0
    ,T_final_dialysis_patient.indicatrice_glycemie_J1
    ,T_final_dialysis_patient.indicatrice_glycemie_J2
    ,T_final_dialysis_patient.indicatrice_glycemie_J3

    ,T_final_dialysis_patient."phlabevents_J0" 
    ,T_final_dialysis_patient."phlabevents_J1" 
    ,T_final_dialysis_patient."phlabevents_J2" 
    ,T_final_dialysis_patient."phlabevents_J3"

    ,T_final_dialysis_patient."lactate_J0(mmol/L)"
    ,T_final_dialysis_patient."lactate_J1(mmol/L)"
    ,T_final_dialysis_patient."lactate_J2(mmol/L)" 
    ,T_final_dialysis_patient."lactate_J3(mmol/L)"


FROM T_final_dialysis_patient



