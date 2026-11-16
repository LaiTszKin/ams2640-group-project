/* ==========================================================================
   05_parity.sas — SAS 端對照程式（F10 前半，REQ-F-F10-1）

   目的：SAS Studio（ODA）跑一次即在 SAS 端的 parity/ 目錄產出
         ① 十四列對照值 sas_parity.csv（cell_id, indicator, group, value, n, value_type）
         ② 機器可讀的 cell_map.csv（cell_id, table, column, row_key, value_type）
         ③ 兩張圖 age_band_dropout.pdf、ability_quartile_graduation.pdf
         下載後放進專案的 output/parity/（見 README_parity.md 的上傳與下載清單）。

   十四格（cell_id → R 端表與列鍵，逐格寫定；同 cell_map.csv）：
     pop_analysis     population_ledger.value        row_key=analysis
     w_both           wealth_four_cell.dropout_rate  row_key=w_both
     w_only_unpaid    wealth_four_cell.dropout_rate  row_key=w_only_unpaid
     w_only_debt      wealth_four_cell.dropout_rate  row_key=w_only_debt
     w_neither        wealth_four_cell.dropout_rate  row_key=w_neither
     a_lt20           age_bands.dropout_rate         row_key=<20
     a_20_24          age_bands.dropout_rate         row_key=20-24
     a_25_29          age_bands.dropout_rate         row_key=25-29
     a_30_39          age_bands.dropout_rate         row_key=30-39
     a_40plus         age_bands.dropout_rate         row_key=40+
     q1               ability_quartiles.graduation_rate row_key=q1
     q2               ability_quartiles.graduation_rate row_key=q2
     q3               ability_quartiles.graduation_rate row_key=q3
     q4               ability_quartiles.graduation_rate row_key=q4

   分組規則（與 R 端逐條對齊，改動即兩端不可比）：
     ① 分析母體：target in ("Graduate", "Dropout")。在讀（Enrolled）不進母體，
        但留在清洗資料集裡。母體人數不寫死，一律由資料算出。
     ② 四格：欠繳 unpaid = (tuition_uptodate = 0)、欠債 indebt = (debtor = 1)。
        原欄編碼即如此；以「繳清 = 1」讀同一份資料會得 phi 的相反符號。
        列序固定為 兩者俱有 → 僅欠繳 → 僅欠債 → 皆無（w_both、w_only_unpaid、
        w_only_debt、w_neither），與 T04 的 cell 鍵及報告家境一節的四個率一一對應。
        各格退學率的分母是**該格人數**，不是全母體（修訂 A-5／A-10／A-22）。
     ③ 年齡帶：左閉右開 [a, b)，切點 20、25、30、40；最後一帶 [40, ∞)。
        帶鍵 a_lt20、a_20_24、a_25_29、a_30_39、a_40plus（與 T05 一致）。
        不可用右閉的讀法：右閉會把邊界值歸到下一帶的左端，得另一組人數。
     ④ 能力分位：能力母體 = 分析母體 ∩ (cu2_grade > 0)（零分是「無成績」，
        不是低能力）。按 cu2_grade **升冪**排序，同分依原始列序（本程式以
        rownum 為第二鍵做穩定排序）；組寬 w = floor(n/4)，前 3 組各 w 人，
        末組收餘數。**不可用 PROC RANK / PCTLDEF 的分位數切點**：切點法在此
        資料上會切出另一組組寬與另一組畢業率。四組鍵 q1–q4（與 T06 一致）。

   精度：值以 best32. 匯出（至少 15 位有效數字），不套用任何顯示格式；
         比率為未格式化的 double，R 端以相對差 1e-9 比對（PRD D10／A-19）。
         n 為整數人數。

   拒絕：資料集載入失敗（三種格式皆不可讀、或缺必要欄）→ 印出嘗試過的每個
         路徑與 SAS 端錯誤原文，標 refuse:input-schema，不寫任何產物。
         任一分母為零 → 標 refuse:empty-denominator，同樣不寫產物（PRD §3）。

   本檔自足：不 %include 00_setup.sas。該檔目前不在專案內（programs/SAS/ 尚未
   建立），故路徑、欄名與切點全部寫在本檔，避免對一個不存在的檔案留下依賴。

   用法：整份貼進 SAS Studio 執行一次。輸出在 SAS 端 &DATADIR/parity/。
   ========================================================================== */

options nodate nonumber nofmterr validvarname = any;
ods noproctitle;

/* ---- 0. 路徑 --------------------------------------------------------------
   ODA 的 Files (Home) 即 /home/&sysuserid；上傳的 .sas7bdat／.xpt／_clean.csv
   與本程式都放在那裡。三種格式任一可用即可，載入順序見 %load_input。
   ------------------------------------------------------------------------- */
%let DATADIR = /home/&sysuserid;
%let BDAT    = &DATADIR/ams2640.sas7bdat;
%let XPTF    = &DATADIR/ams2640.xpt;
%let CSVF    = &DATADIR/ams2640_clean.csv;
%let OUTDIR  = &DATADIR/parity;

/* 輸出目錄不存在時由 SAS 自行建立（DLDCREATEDIR 對 fileref 生效） */
options dlcreatedir;
filename cmfile "&OUTDIR/cell_map.csv";
filename spfile "&OUTDIR/sas_parity.csv";
filename abpdf  "&OUTDIR/age_band_dropout.pdf";
filename qgpdf  "&OUTDIR/ability_quartile_graduation.pdf";

/* 必要欄（清洗資料集的 SAS 欄名，已由 01_prep_data.R 正規化為 ≤32 字元） */
%let NEEDCOLS = target debtor tuition_uptodate age_enrol cu2_grade;

/* ---- 1. 十四列的骨架（固定列序，同時是 cell_map.csv 的來源） ---------------
   cell_id → R 端表／欄／列鍵。row_key 為 R 表該列的鍵值：age_bands 的 band
   欄存的就是 <20 … 40+，故 row_key 用該字面值，不是 a_25_29 一類的 cell_id
   別名；population_ledger 由 (population, metric) = (analysis, analysis) 選列，
   row_key 記 metric。grp 為 sas_parity.csv 的 group 值，定義上等於 row_key。
   ord 即十四格的固定序，下游「第一個不符」以它為唯一定義。
   （DATALINES 放在最上層、不放在 macro 內，避免在 %do 區塊裡讀內嵌資料。）
   ------------------------------------------------------------------------- */
data work.cells;
  length cell_id $16 rtable $24 rcolumn $16 row_key $16 indicator $16
         grp $16 value_type $5;
  infile datalines dsd truncover;
  input cell_id $ rtable $ rcolumn $ row_key $ indicator $ value_type $;
  grp = row_key;
  ord + 1;
  datalines;
pop_analysis,population_ledger.csv,value,analysis,pop_analysis,count
w_both,wealth_four_cell.csv,dropout_rate,w_both,dropout_rate,rate
w_only_unpaid,wealth_four_cell.csv,dropout_rate,w_only_unpaid,dropout_rate,rate
w_only_debt,wealth_four_cell.csv,dropout_rate,w_only_debt,dropout_rate,rate
w_neither,wealth_four_cell.csv,dropout_rate,w_neither,dropout_rate,rate
a_lt20,age_bands.csv,dropout_rate,<20,dropout_rate,rate
a_20_24,age_bands.csv,dropout_rate,20-24,dropout_rate,rate
a_25_29,age_bands.csv,dropout_rate,25-29,dropout_rate,rate
a_30_39,age_bands.csv,dropout_rate,30-39,dropout_rate,rate
a_40plus,age_bands.csv,dropout_rate,40+,dropout_rate,rate
q1,ability_quartiles.csv,graduation_rate,q1,graduation_rate,rate
q2,ability_quartiles.csv,graduation_rate,q2,graduation_rate,rate
q3,ability_quartiles.csv,graduation_rate,q3,graduation_rate,rate
q4,ability_quartiles.csv,graduation_rate,q4,graduation_rate,rate
;
run;

/* 依 ord 排序：合併與匯出都以它為唯一鍵 */
proc sort data = work.cells; by ord; run;

/* ---- 2. 載入清洗資料集（sas7bdat → xpt → csv） -------------------------- */

/* load_input：依序嘗試三種格式，成功即停。失敗時保留每個路徑的錯誤原文。
   RUN_OK=1 表可續跑；SRC_USED 記實際來源。 */
%macro load_input;
  %global RUN_OK SRC_USED;
  %let RUN_OK = 0;
  %let SRC_USED = (none);

  /* ① .sas7bdat（主格式） */
  %if %sysfunc(fileexist("&BDAT")) %then %do;
    libname pj "&DATADIR" access=readonly;
    %if %sysfunc(exist(pj.ams2640)) %then %do;
      data work.raw;
        set pj.ams2640;
      run;
      %if &syserr = 0 %then %do;
        %let RUN_OK = 1;
        %let SRC_USED = &BDAT;
        %put NOTE: [05_parity] 載入 &BDAT（libname pj，成員 ams2640）;
      %end;
      %else %put ERROR: [05_parity] 載入 &BDAT 失敗：&syserrortext;
    %end;
    %else %put ERROR: [05_parity] &BDAT 存在但 libref 內無成員 ams2640：&syserrortext;
    libname pj clear;
  %end;
  %else %put NOTE: [05_parity] 嘗試 &BDAT：檔案不存在（fileexist=0）;

  /* ② .xpt（備援一，haven 寫出的 transport 檔） */
  %if &RUN_OK = 0 %then %do;
    %if %sysfunc(fileexist("&XPTF")) %then %do;
      proc cimport library=work infile="&XPTF";
      run;
      %if %sysfunc(exist(work.ams2640)) %then %do;
        data work.raw;
          set work.ams2640;
        run;
        %if &syserr = 0 %then %do;
          %let RUN_OK = 1;
          %let SRC_USED = &XPTF;
          %put NOTE: [05_parity] 載入 &XPTF（proc cimport）;
        %end;
        %else %put ERROR: [05_parity] cimport 後讀 &XPTF 失敗：&syserrortext;
      %end;
      %else %put ERROR: [05_parity] &XPTF 存在但 cimport 未產生 work.ams2640：&syserrortext;
    %end;
    %else %put NOTE: [05_parity] 嘗試 &XPTF：檔案不存在（fileexist=0）;
  %end;

  /* ③ _clean.csv（備援二）。CSV 保留原始問卷欄名（含空格與括號），
     故以 name literal 取名後複製成與 sas7bdat 相同的正規化欄名。 */
  %if &RUN_OK = 0 %then %do;
    %if %sysfunc(fileexist("&CSVF")) %then %do;
      proc import datafile="&CSVF" out=work.csvraw dbms=csv replace;
        getnames = yes;
        guessingrows = max;
      run;
      %if &syserr = 0 %then %do;
        data work.raw;
          set work.csvraw;
          debtor           = Debtor;
          tuition_uptodate = 'Tuition fees up to date'n;
          age_enrol        = 'Age at enrollment'n;
          cu2_grade        = 'Curricular units 2nd sem (grade)'n;
          keep debtor tuition_uptodate age_enrol cu2_grade target;
        run;
        %if &syserr = 0 %then %do;
          %let RUN_OK = 1;
          %let SRC_USED = &CSVF;
          %put NOTE: [05_parity] 載入 &CSVF（proc import + name literal 改名）;
        %end;
        %else %put ERROR: [05_parity] 讀 &CSVF 後改名失敗：&syserrortext;
      %end;
      %else %put ERROR: [05_parity] proc import &CSVF 失敗：&syserrortext;
    %end;
    %else %put NOTE: [05_parity] 嘗試 &CSVF：檔案不存在（fileexist=0）;
  %end;

  /* ④ 必要欄檢查：載入成功但欄不符，同樣算 refuse:input-schema */
  %if &RUN_OK = 1 %then %do;
    proc sql noprint;
      select count(distinct upcase(name)) into :HAVE_N trimmed
        from dictionary.columns
       where libname = "WORK" and memname = "RAW"
         and upcase(name) in ("TARGET", "DEBTOR", "TUITION_UPTODATE", "AGE_ENROL", "CU2_GRADE");
      select upcase(name) into :HAVE_LIST separated by " "
        from dictionary.columns
       where libname = "WORK" and memname = "RAW";
    quit;
    %if &HAVE_N < 5 %then %do;
      %let RUN_OK = 0;
      %put ERROR: [05_parity] refuse:input-schema 清洗資料集缺必要欄（應有 &NEEDCOLS，實得 &HAVE_N/5）;
      %put ERROR: [05_parity] work.raw 現有欄：&HAVE_LIST;
    %end;
    %else %put NOTE: [05_parity] 必要欄齊備：&NEEDCOLS;
  %end;
%mend load_input;

/* ---- 3. 主體 ------------------------------------------------------------ */

%macro main;
  %load_input;

  %if &RUN_OK = 0 %then %do;
    %put ERROR: [05_parity] refuse:input-schema — 已嘗試 &BDAT、&XPTF、&CSVF，皆不可用；
    %put ERROR: [05_parity] 停止：不寫 cell_map.csv、sas_parity.csv 或任何圖。;
    %put ERROR: [05_parity] 下一步：確認三個檔案已上傳到 &DATADIR（Files (Home)），再重跑。;
  %end;
  %else %do;

    %put NOTE: [05_parity] SAS 版本：&sysver（&sysvlong）;
    %put NOTE: [05_parity] 來源：&SRC_USED;

    /* ---- 3.1 分析母體、四格與年齡帶 ---------------------------------- */
    data work.an;
      set work.raw;
      length cell $16 band $8;

      /* 原始列序：能力分位同分時的次序（與 R 端 radix 穩定排序的第二鍵相同） */
      rownum + 1;

      /* 分析母體界線：已畢業加已退學；在讀不進母體 */
      in_analysis = (target in ("Graduate", "Dropout"));
      dropout     = (target = "Dropout");
      graduate    = (target = "Graduate");

      /* 四格編碼（原欄定義）：欠繳 = 學費未繳清（= 0）、欠債 = Debtor（= 1）。
         任一欄缺值時該列不進任何一格，與 R 端 NA 不入格一致。
         列序：兩者俱有 → 僅欠繳 → 僅欠債 → 皆無（修訂 A-22）。 */
      if missing(tuition_uptodate) or missing(debtor) then do;
        _unpaid = .;
        _indebt = .;
      end;
      else do;
        _unpaid = (tuition_uptodate = 0);
        _indebt = (debtor = 1);
      end;

      if      _unpaid = 1 and _indebt = 1 then cell = "w_both";
      else if _unpaid = 1 and _indebt = 0 then cell = "w_only_unpaid";
      else if _unpaid = 0 and _indebt = 1 then cell = "w_only_debt";
      else if _unpaid = 0 and _indebt = 0 then cell = "w_neither";
      else cell = "";

      /* 年齡帶：左閉右開 [a, b)，切點 20／25／30／40，最後一帶 [40, ∞)。
         SAS 不支援連續比較（20 <= x < 25 會恆真），一律寫成 A <= x and x < B。 */
      if missing(age_enrol) then band = "";
      else if age_enrol < 20 then band = "a_lt20";
      else if 20 <= age_enrol and age_enrol < 25 then band = "a_20_24";
      else if 25 <= age_enrol and age_enrol < 30 then band = "a_25_29";
      else if 30 <= age_enrol and age_enrol < 40 then band = "a_30_39";
      else band = "a_40plus";
    run;

    proc sql noprint;
      select sum(in_analysis) into :POP_N trimmed from work.an;
    quit;
    %put NOTE: [05_parity] 母體界線 target in (Graduate, Dropout)；分析母體 n=&POP_N;

    /* ---- 3.2 能力母體與等量切四組 ------------------------------------ */
    /* 剔除第二學期零分（無成績，不是低能力）；cut 只用到的欄一起帶走 */
    data work.abil;
      set work.an;
      if in_analysis = 1 and cu2_grade > 0;
      keep rownum cu2_grade graduate;
    run;

    /* 升冪、同分依原始列序（rownum 為第二鍵） */
    proc sort data = work.abil out = work.abil_sorted;
      by cu2_grade rownum;
    run;

    data work.q;
      if 0 then set work.abil_sorted nobs = _TOTAL;
      retain _POS 0 _W 0;
      set work.abil_sorted;

      _POS + 1;
      _W = int(_TOTAL / 4);          /* 組寬 floor(n/4)；不取任何分位數切點 */
      if _W < 1 then do;
        put "ERROR: [05_parity] refuse:empty-denominator 能力母體不足等量切成 4 組，n=" _TOTAL;
        stop;
      end;

      /* 前 3 組各 _W 人，末組收餘數（與 T06 的 equal_split 同） */
      if _POS <= 3 * _W then q = ceil(_POS / _W);
      else q = 4;
    run;

    /* ---- 3.3 十四格的數值 -------------------------------------------- */
    /* 每格一條 SELECT：n 為該格人數，value 為比率（或母體計數）。
       ord 與 cell_id 的對應在 2.4 的骨架裡；此處只出 (ord, n, value)。 */
    proc sql;
      create table work.vals as
        /* 1 pop_analysis：分析母體人數（count） */
        select 1 as ord, sum(in_analysis) as n, sum(in_analysis) as value
          from work.an

        /* 2-5 四格退學率，分母為該格人數 */
        union all
        select 2 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and cell = "w_both"
        union all
        select 3 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and cell = "w_only_unpaid"
        union all
        select 4 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and cell = "w_only_debt"
        union all
        select 5 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and cell = "w_neither"

        /* 6-10 五帶退學率，分母為該帶人數 */
        union all
        select 6 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and band = "a_lt20"
        union all
        select 7 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and band = "a_20_24"
        union all
        select 8 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and band = "a_25_29"
        union all
        select 9 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and band = "a_30_39"
        union all
        select 10 as ord, count(*) as n, mean(dropout) as value
          from work.an where in_analysis = 1 and band = "a_40plus"

        /* 11-14 四組畢業率，分母為該組人數 */
        union all
        select 11 as ord, count(*) as n, mean(graduate) as value
          from work.q where q = 1
        union all
        select 12 as ord, count(*) as n, mean(graduate) as value
          from work.q where q = 2
        union all
        select 13 as ord, count(*) as n, mean(graduate) as value
          from work.q where q = 3
        union all
        select 14 as ord, count(*) as n, mean(graduate) as value
          from work.q where q = 4
      ;
    quit;

    /* ---- 3.4 依 ord 合併（骨架在段 1 已建立） ------------------------- */
    proc sort data = work.cells; by ord; run;
    proc sort data = work.vals;  by ord; run;

    data work.parity;
      merge work.cells work.vals;
      by ord;
    run;

    /* ---- 3.5 空分母守衛（PRD §3：任一格為空即拒絕） ------------------ */
    proc sql noprint;
      select count(*) into :N_BAD trimmed
        from work.parity
       where n = 0 or missing(value);
    quit;

    %if &N_BAD > 0 %then %do;
      %put ERROR: [05_parity] refuse:empty-denominator — 以下格的分母為零，停止輸出：;
      proc print data = work.parity noobs;
        where n = 0 or missing(value);
        var ord cell_id n value;
      run;
    %end;
    %else %do;

      /* ---- 3.6 匯出對照值與 cell_map --------------------------------- */
      /* 值以 best32. 轉成文字後原樣寫出：不套顯示格式、不四捨五入到四位，
         使 R 端能以相對差 1e-9 比對未格式化的 double。 */
      /* 以 catx 組行再以 $VARYING. 寫定長：避免 PUT 把字元欄補blank 到宣告長度，
         也避免任何一個值被截斷。 */
      data _null_;
        file cmfile lrecl = 512;
        length line $512 len 8;
        set work.cells;
        if _n_ = 1 then do;
          line = "cell_id,table,column,row_key,value_type";
          len  = length(line);
          put line $varying512. len;
        end;
        line = catx(",", cell_id, rtable, rcolumn, row_key, value_type);
        len  = length(line);
        put line $varying512. len;
      run;

      data _null_;
        file spfile lrecl = 512;
        length line $512 len 8 valtxt $32 ntxt $12;
        set work.parity;
        valtxt = strip(put(value, best32.));
        ntxt   = strip(put(n, best32.));
        if _n_ = 1 then do;
          line = "cell_id,indicator,group,value,n,value_type";
          len  = length(line);
          put line $varying512. len;
        end;
        line = catx(",", cell_id, indicator, grp, valtxt, ntxt, value_type);
        len  = length(line);
        put line $varying512. len;
      run;

      /* ---- 3.7 兩張圖 -------------------------------------------------- */
      proc sql noprint;
        select count(*) into :ABILITY_N trimmed from work.q;
      quit;

      /* 年齡帶：以 band_ord 保住固定帶序，標籤用區間讀法 */
      proc sql;
        create table work.chart_age as
          select band,
                 count(*)        as n,
                 mean(dropout)   as dropout_rate,
                 case band
                   when "a_lt20"    then 1
                   when "a_20_24"   then 2
                   when "a_25_29"   then 3
                   when "a_30_39"   then 4
                   when "a_40plus"  then 5
                 end             as band_ord
            from work.an
           where in_analysis = 1 and band ne ""
           group by band
           order by band_ord;
      quit;

      data work.chart_age;
        set work.chart_age;
        length band_label $10;
        band_label = choosec(band_ord, "<20", "20-24", "25-29", "30-39", "40+");
      run;

      /* 能力分位：q1..q4 固定序 */
      proc sql;
        create table work.chart_q as
          select q as qnum,
                 count(*)      as n,
                 mean(graduate) as graduation_rate
            from work.q
           group by q
           order by q;
      quit;

      data work.chart_q;
        set work.chart_q;
        length q_label $8;
        q_label = cats("q", qnum);
      run;

      ods graphics / reset = all width = 6in height = 4in;
      ods pdf file = abpdf style = journal;
      title "Dropout rate by age band (analysis population, n=&POP_N)";
      footnote "Source: ams2640 (SAS end), 05_parity.sas; band = left-closed right-open, breaks 20/25/30/40";
      proc sgplot data = work.chart_age noautolegend;
        vbar band_label / response = dropout_rate stat = mean
             datalabel datalabelformat = 6.4 fillattrs = (color = cx9ecae1);
        yaxis label = "Dropout rate" values = (0 to 1 by 0.1) grid;
        xaxis label = "Age band (years)";
      run;
      title; footnote;
      ods pdf close;

      ods pdf file = qgpdf style = journal;
      title "Graduation rate by second-semester grade quartile (n=&ABILITY_N)";
      footnote "Source: ams2640 (SAS end), 05_parity.sas; equal split on cu2_grade, ties by original row order";
      proc sgplot data = work.chart_q noautolegend;
        vbar q_label / response = graduation_rate stat = mean
             datalabel datalabelformat = 6.4 fillattrs = (color = cx9ecae1);
        yaxis label = "Graduation rate" values = (0 to 1 by 0.1) grid;
        xaxis label = "Quartile (q1 = lowest cu2_grade)";
      run;
      title; footnote;
      ods pdf close;

      /* ---- 3.8 執行記錄的結尾 ----------------------------------------- */
      proc print data = work.parity noobs label;
        var ord cell_id indicator grp n value value_type;
        format value best32.;
        label cell_id = "cell_id" grp = "group" n = "n"
              value = "value (best32.)" value_type = "value_type";
      run;

      %put NOTE: [05_parity] 十四格已寫出：&OUTDIR/sas_parity.csv（值 best32.）;
      %put NOTE: [05_parity] cell_map 已寫出：&OUTDIR/cell_map.csv;
      %put NOTE: [05_parity] 圖：&OUTDIR/age_band_dropout.pdf、&OUTDIR/ability_quartile_graduation.pdf;
      %put NOTE: [05_parity] 下一步：把上述四個檔下載到專案的 output/parity/，再跑 Rscript programs/R/90_parity.R;
    %end;
  %end;
%mend main;

%main;
