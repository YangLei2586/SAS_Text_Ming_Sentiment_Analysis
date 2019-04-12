data &em_score_output;
set &em_score_output;
*------------------------------------------------------------*;
* EM SCORE CODE;
*------------------------------------------------------------*;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: SAMPLE;
* NODE: FIMPORT;
*------------------------------------------------------------*;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: TM;
* NODE: TextParsing;
*------------------------------------------------------------*;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: TM;
* NODE: TextFilter;
*------------------------------------------------------------*;
_document_ = _n_;
rc=tgscore(textfield,"termloc.TextFilter_tmconfig", "termloc.TextFilter_filtterms", "TextFilter_out", "&_multifile", 0);
drop rc;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: TM;
* NODE: TextCluster;
*------------------------------------------------------------*;
%tmc_doc_score(import=&em_score_output,export=work._newexport,
termds=termloc.TextFilter_filtterms, configds=termloc.TextCluster_tmconfig,
clusters=termloc.TextCluster_clusters, emoutstat=termloc.TextCluster_emoutstat,
_scrout=work.TextFilter_out, svd_u=termloc.TextCluster_svd_u, svd_s=termloc.TextCluster_svd_s, prefix=TextCluster);
data &em_score_output; set work._newexport;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: TM;
* NODE: TextTopic;
*------------------------------------------------------------*;
/* First we create a Weighted TMOUT Data Set based on weighted terms*/
proc tmutil data=work.TextFilter_out key=termloc.TextFilter_filtterms;
control init release;
weight cellwgt=LOG in_weight=termloc.TextFilter_filtterms (keep=key weight);
output out=work._weighted_tmout;

%row_pivot_normalize(transds=work._weighted_tmout, outtransds=WORK.TMOUTNORM,
      col_sumds=work._termsumds,row=_document_,col=_termnum_,entry=_count_,
      pivot=0.7,tmt_config=termloc.TextFilter_tmconfig,tmt_train=0,prefix=TextTopic);

/*initialize topics and termtopics datasets in case they do not exist (0 topics case)*/
%macro tmt_check_topics_exist;
%if(^%sysfunc(exist(termloc.TextTopic_topics))) %then %do;
   proc sql noprint; create table termloc.TextTopic_topics
   (_topicid decimal, _docCutoff decimal, _termCutoff decimal, _name char(1024), _cat char(4), /* _apply char(1), */ _numterms decimal, _numdocs decimal, _displayCat char(200) );
   quit;
%end;
%if(^%sysfunc(exist(termloc.TextTopic_termtopics))) %then %do;
   proc sql noprint; create table termloc.TextTopic_termtopics
   (_topicid decimal, _weight decimal, _termid decimal);
   quit;
%end;
%mend tmt_check_topics_exist;
%tmt_check_topics_exist;
data work.TextTopic_termtopics; set termloc.TextTopic_termtopics; run;
data work.TextTopic_topics; set termloc.TextTopic_topics; run;
%tmt_doc_score(termtopds=work.TextTopic_termtopics, docds=&em_score_output,
outds=WORK.TMOUTNORM, topicds=work.TextTopic_topics, newdocds=work._newdocds, scoring=yes,
termsumds=work._termsumds, prefix=TextTopic_,pivot=0.7);
data &em_score_output; set work._newdocds;
*------------------------------------------------------------*;
* TOOL: Extension Class;
* TYPE: MODEL;
* NODE: Tree;
*------------------------------------------------------------*;
****************************************************************;
******             DECISION TREE SCORING CODE             ******;
****************************************************************;

******         LENGTHS OF NEW CHARACTER VARIABLES         ******;
LENGTH I_Target_Subject  $    1;
LENGTH U_Target_Subject  $    1;
LENGTH _WARN_  $    4;

******              LABELS FOR NEW VARIABLES              ******;
label _NODE_ = 'Node' ;
label _LEAF_ = 'Leaf' ;
label P_Target_SubjectA = 'Predicted: Target_Subject=A' ;
label P_Target_SubjectS = 'Predicted: Target_Subject=S' ;
label P_Target_SubjectW = 'Predicted: Target_Subject=W' ;
label Q_Target_SubjectA = 'Unadjusted P: Target_Subject=A' ;
label Q_Target_SubjectS = 'Unadjusted P: Target_Subject=S' ;
label Q_Target_SubjectW = 'Unadjusted P: Target_Subject=W' ;
label I_Target_Subject = 'Into: Target_Subject' ;
label U_Target_Subject = 'Unnormalized Into: Target_Subject' ;
label _WARN_ = 'Warnings' ;


******      TEMPORARY VARIABLES FOR FORMATTED VALUES      ******;
LENGTH _ARBFMT_1 $      1; DROP _ARBFMT_1;
_ARBFMT_1 = ' '; /* Initialize to avoid warning. */


******             ASSIGN OBSERVATION TO NODE             ******;
IF  NOT MISSING(TextTopic_raw1 ) AND
                0.1115 <= TextTopic_raw1  THEN DO;
  _NODE_  =                    3;
  _LEAF_  =                    3;
  P_Target_SubjectA  =                    0;
  P_Target_SubjectS  =                    1;
  P_Target_SubjectW  =                    0;
  Q_Target_SubjectA  =                    0;
  Q_Target_SubjectS  =                    1;
  Q_Target_SubjectW  =                    0;
  I_Target_Subject  = 'S' ;
  U_Target_Subject  = 'S' ;
  END;
ELSE DO;
  IF  NOT MISSING(TextCluster_SVD1 ) AND
    TextCluster_SVD1  <     0.03209465561665 THEN DO;
    _NODE_  =                    4;
    _LEAF_  =                    1;
    P_Target_SubjectA  =                    0;
    P_Target_SubjectS  =                    0;
    P_Target_SubjectW  =                    1;
    Q_Target_SubjectA  =                    0;
    Q_Target_SubjectS  =                    0;
    Q_Target_SubjectW  =                    1;
    I_Target_Subject  = 'W' ;
    U_Target_Subject  = 'W' ;
    END;
  ELSE DO;
    _NODE_  =                    5;
    _LEAF_  =                    2;
    P_Target_SubjectA  =                    1;
    P_Target_SubjectS  =                    0;
    P_Target_SubjectW  =                    0;
    Q_Target_SubjectA  =                    1;
    Q_Target_SubjectS  =                    0;
    Q_Target_SubjectW  =                    0;
    I_Target_Subject  = 'A' ;
    U_Target_Subject  = 'A' ;
    END;
  END;

****************************************************************;
******          END OF DECISION TREE SCORING CODE         ******;
****************************************************************;

drop _LEAF_;
*------------------------------------------------------------*;
* TOOL: Score Node;
* TYPE: ASSESS;
* NODE: Score;
*------------------------------------------------------------*;
*------------------------------------------------------------*;
* Score: Creating Fixed Names;
*------------------------------------------------------------*;
LABEL EM_SEGMENT = 'Segment';
EM_SEGMENT = TextCluster_cluster_;
LENGTH EM_EVENTPROBABILITY 8;
LABEL EM_EVENTPROBABILITY = 'Probability for level W of Target_Subject';
EM_EVENTPROBABILITY = P_Target_SubjectW;
LENGTH EM_PROBABILITY 8;
LABEL EM_PROBABILITY = 'Probability of Classification';
EM_PROBABILITY =
max(
P_Target_SubjectW
,
P_Target_SubjectS
,
P_Target_SubjectA
);
LENGTH EM_CLASSIFICATION $%dmnorlen;
LABEL EM_CLASSIFICATION = "Prediction for Target_Subject";
EM_CLASSIFICATION = I_Target_Subject;
