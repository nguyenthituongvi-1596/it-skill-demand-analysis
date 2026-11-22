﻿/* =====================================================
   FINAL PROJECT - VTI Academy
   Database: VTI_SkillDemand
   Dữ liệu: khảo sát Stack Overflow + tin tuyển dụng 123job.vn
   Stakeholder: Quản lý đào tạo (thiết kế chương trình)
   ===================================================== */

-- ========== PHẦN 1: TẠO DATABASE ==========
-- Xóa database cũ nếu đã có, để chạy lại cả file nhiều lần không bị lỗi "already exists"
USE master;
GO
DROP DATABASE IF EXISTS VTI_SkillDemand;
GO
CREATE DATABASE VTI_SkillDemand;
GO
USE VTI_SkillDemand;
GO

-- ========== PHẦN 2: TẠO BẢNG ==========
-- Bảng 1: mỗi dòng = 1 người trả lời khảo sát
CREATE TABLE survey_respondents (
    respondent_id             INT NOT NULL PRIMARY KEY,
    main_branch               NVARCHAR(100),
    hobbyist                  NVARCHAR(10),
    employment                NVARCHAR(50),
    country                   NVARCHAR(100),
    is_vietnam                BIT,
    student                   NVARCHAR(50),
    education_level           NVARCHAR(150),
    undergrad_major           NVARCHAR(150),
    org_size                  NVARCHAR(100),
    dev_type                  NVARCHAR(1000),
    years_code                FLOAT,
    age_first_code            FLOAT,
    years_code_pro            FLOAT,
    exp_group                 NVARCHAR(20),
    career_satisfaction       NVARCHAR(50),
    job_satisfaction          NVARCHAR(50),
    job_seek                  NVARCHAR(100),
    work_week_hours           FLOAT,
    annual_comp_usd           FLOAT,
    work_remote               NVARCHAR(100),
    operating_system          NVARCHAR(30),
    age                       FLOAT,
    gender                    NVARCHAR(50),
    answered_language_worked  BIT,
    answered_language_desire  BIT,
    answered_database_worked  BIT,
    answered_database_desire  BIT,
    answered_framework_worked BIT,
    answered_framework_desire BIT,
    answered_platform_worked  BIT,
    answered_platform_desire  BIT,
    answered_ide              BIT
);

-- Bảng 2: mỗi dòng = 1 người x 1 kỹ năng x 1 trạng thái
CREATE TABLE survey_skills (
    respondent_id INT          NOT NULL,
    skill_group   NVARCHAR(20) NOT NULL,
    skill         NVARCHAR(50) NOT NULL,
    status        NVARCHAR(20) NOT NULL,
    source_field  NVARCHAR(50),
    CONSTRAINT FK_survey_skills_respondent
        FOREIGN KEY (respondent_id) REFERENCES survey_respondents(respondent_id)
);

-- Bảng 3: mỗi dòng = 1 tin tuyển dụng trên 123job
-- job_key: mã số 1, 2, 3... làm khóa chính (an toàn ở mọi công cụ)
-- job_id: mã đuôi URL, phân biệt chữ hoa/thường (vd 'ND4ZKg1Yrv' khác 'nd4zkg1yrv'), giữ để truy vết
CREATE TABLE job_postings (
    job_key            INT NOT NULL PRIMARY KEY,
    job_id             NVARCHAR(20) COLLATE Latin1_General_CS_AS NOT NULL UNIQUE,
    job_title          NVARCHAR(255),
    company            NVARCHAR(255),
    province           NVARCHAR(50),
    industry           NVARCHAR(100),
    description_length INT,
    has_any_skill      BIT,
    job_url            NVARCHAR(400)
);

-- Bảng 4: mỗi dòng = 1 tin x 1 kỹ năng được yêu cầu
CREATE TABLE job_skills (
    job_key     INT NOT NULL,
    job_id      NVARCHAR(20) COLLATE Latin1_General_CS_AS NOT NULL,
    skill_group NVARCHAR(20) NOT NULL,
    skill       NVARCHAR(50) NOT NULL,
    status      NVARCHAR(20) NOT NULL,
    CONSTRAINT FK_job_skills_job
        FOREIGN KEY (job_key) REFERENCES job_postings(job_key)
);

-- ========== PHẦN 3: NHẬP DỮ LIỆU ==========
-- 3a. INSERT mẫu: thêm thử 1 dòng bằng tay để kiểm tra bảng, rồi xóa đi
INSERT INTO job_postings (job_key, job_id, job_title, company, province, industry,
                          description_length, has_any_skill, job_url)
VALUES (999999, 'TEST0001', N'Lập trình viên Python (dòng thử)', N'Công ty Demo',
        N'Hà Nội', N'IT phần mềm', 1000, 1, 'https://example.com');

SELECT * FROM job_postings WHERE job_id = 'TEST0001';   -- xem dòng vừa thêm
DELETE FROM job_postings WHERE job_id = 'TEST0001';     -- xóa dòng thử

-- 3b. BULK INSERT: nạp toàn bộ dữ liệu từ CSV (bảng cha trước, bảng con sau)
BULK INSERT survey_respondents FROM 'C:\vti\clean_csv\survey_respondents.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS);

BULK INSERT survey_skills FROM 'C:\vti\clean_csv\survey_skills.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, CHECK_CONSTRAINTS);

BULK INSERT job_postings FROM 'C:\vti\clean_csv\job_postings.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS);

BULK INSERT job_skills FROM 'C:\vti\clean_csv\job_skills.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, CHECK_CONSTRAINTS);

-- 3c. Kiểm tra số dòng: phải khớp số dòng của 4 file CSV do file 02 xuất ra
--     (với dữ liệu hiện tại: 11398 / 382659 / 423 / 1212)
SELECT 'survey_respondents' AS bang, COUNT(*) AS so_dong FROM survey_respondents
UNION ALL SELECT 'survey_skills', COUNT(*) FROM survey_skills
UNION ALL SELECT 'job_postings',  COUNT(*) FROM job_postings
UNION ALL SELECT 'job_skills',    COUNT(*) FROM job_skills;

-- ========== PHẦN 4: TRẢ LỜI CÂU HỎI EDA (kiểm tra chéo với Python) ==========

-- Q1a: Top 10 ngôn ngữ đang dùng (% trên số người có trả lời câu hỏi này)
SELECT TOP 10
    s.skill,
    COUNT(DISTINCT s.respondent_id) AS so_nguoi,
    CAST(100.0 * COUNT(DISTINCT s.respondent_id)
         / (SELECT SUM(CAST(answered_language_worked AS INT)) FROM survey_respondents)
         AS DECIMAL(5,1)) AS pct
FROM survey_skills AS s
WHERE s.skill_group = 'language'
  AND s.status = 'worked_with'
GROUP BY s.skill
ORDER BY so_nguoi DESC;

-- Q1b: % đang dùng, % muốn dùng và chênh lệch (gap) của từng ngôn ngữ
WITH worked AS (
    SELECT skill, COUNT(DISTINCT respondent_id) * 100.0
           / (SELECT SUM(CAST(answered_language_worked AS INT)) FROM survey_respondents) AS pct_worked
    FROM survey_skills
    WHERE skill_group = 'language' AND status = 'worked_with'
    GROUP BY skill
),
desire AS (
    SELECT skill, COUNT(DISTINCT respondent_id) * 100.0
           / (SELECT SUM(CAST(answered_language_desire AS INT)) FROM survey_respondents) AS pct_desire
    FROM survey_skills
    WHERE skill_group = 'language' AND status = 'desire_next_year'
    GROUP BY skill
)
SELECT
    w.skill,
    CAST(w.pct_worked AS DECIMAL(5,1))                AS pct_worked,
    CAST(d.pct_desire AS DECIMAL(5,1))                AS pct_desire,
    CAST(d.pct_desire - w.pct_worked AS DECIMAL(5,1)) AS gap
FROM worked AS w
JOIN desire AS d ON w.skill = d.skill
WHERE w.pct_worked >= 5          -- bỏ ngôn ngữ quá hiếm
ORDER BY gap DESC;

-- Q1c: Top 10 ngôn ngữ được nhắc trong tin 123job (% trên tổng số tin)
SELECT TOP 10
    js.skill,
    COUNT(DISTINCT js.job_key) AS so_tin,
    CAST(100.0 * COUNT(DISTINCT js.job_key)
         / (SELECT COUNT(*) FROM job_postings) AS DECIMAL(5,1)) AS pct_tin
FROM job_skills AS js
WHERE js.skill_group = 'language'
GROUP BY js.skill
ORDER BY so_tin DESC;

-- Q2a: % đang dùng, % muốn dùng, chênh lệch của từng hệ CSDL, kèm loại
WITH worked AS (
    SELECT skill, COUNT(DISTINCT respondent_id) * 100.0
           / (SELECT SUM(CAST(answered_database_worked AS INT)) FROM survey_respondents) AS pct_worked
    FROM survey_skills
    WHERE skill_group = 'database' AND status = 'worked_with'
    GROUP BY skill
),
desire AS (
    SELECT skill, COUNT(DISTINCT respondent_id) * 100.0
           / (SELECT SUM(CAST(answered_database_desire AS INT)) FROM survey_respondents) AS pct_desire
    FROM survey_skills
    WHERE skill_group = 'database' AND status = 'desire_next_year'
    GROUP BY skill
)
SELECT
    w.skill,
    CASE WHEN w.skill IN ('MongoDB', 'Redis', 'Elasticsearch', 'Cassandra', 'DynamoDB',
                          'Couchbase', 'Firebase')
         THEN 'NoSQL' ELSE N'Quan hệ' END            AS loai,
    CAST(w.pct_worked AS DECIMAL(5,1))                AS pct_worked,
    CAST(d.pct_desire AS DECIMAL(5,1))                AS pct_desire,
    CAST(d.pct_desire - w.pct_worked AS DECIMAL(5,1)) AS gap
FROM worked AS w
JOIN desire AS d ON w.skill = d.skill
ORDER BY w.pct_worked DESC;

-- Q2b: % người dùng/muốn dùng ít nhất 1 CSDL quan hệ, ít nhất 1 NoSQL
WITH gan_loai AS (
    SELECT respondent_id, status,
           CASE WHEN skill IN ('MongoDB', 'Redis', 'Elasticsearch', 'Cassandra', 'DynamoDB',
                               'Couchbase', 'Firebase')
                THEN 'NoSQL' ELSE N'Quan hệ' END AS loai
    FROM survey_skills
    WHERE skill_group = 'database'
)
SELECT
    loai,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN status = 'worked_with' THEN respondent_id END)
         / (SELECT SUM(CAST(answered_database_worked AS INT)) FROM survey_respondents) AS DECIMAL(5,1)) AS pct_worked,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN status = 'desire_next_year' THEN respondent_id END)
         / (SELECT SUM(CAST(answered_database_desire AS INT)) FROM survey_respondents) AS DECIMAL(5,1)) AS pct_desire
FROM gan_loai
GROUP BY loai;

-- Q3: Top 10 IDE (% trên số người có trả lời câu hỏi IDE)
SELECT TOP 10
    skill AS ide,
    COUNT(DISTINCT respondent_id) AS so_nguoi,
    CAST(100.0 * COUNT(DISTINCT respondent_id)
         / (SELECT SUM(CAST(answered_ide AS INT)) FROM survey_respondents) AS DECIMAL(5,1)) AS pct
FROM survey_skills
WHERE skill_group = 'ide'
GROUP BY skill
ORDER BY so_nguoi DESC;

-- Q4a: Framework & platform có chênh lệch (muốn - đang dùng) lớn nhất
WITH pct AS (
    SELECT s.skill_group, s.skill, s.status,
           COUNT(DISTINCT s.respondent_id) * 100.0 /
           CASE
               WHEN s.skill_group = 'framework'     AND s.status = 'worked_with'
                    THEN (SELECT SUM(CAST(answered_framework_worked AS INT)) FROM survey_respondents)
               WHEN s.skill_group = 'framework'     AND s.status = 'desire_next_year'
                    THEN (SELECT SUM(CAST(answered_framework_desire AS INT)) FROM survey_respondents)
               WHEN s.skill_group = 'platform_tool' AND s.status = 'worked_with'
                    THEN (SELECT SUM(CAST(answered_platform_worked AS INT)) FROM survey_respondents)
               ELSE      (SELECT SUM(CAST(answered_platform_desire AS INT)) FROM survey_respondents)
           END AS pct
    FROM survey_skills AS s
    WHERE s.skill_group IN ('framework', 'platform_tool')
    GROUP BY s.skill_group, s.skill, s.status
)
SELECT TOP 10
    w.skill_group, w.skill,
    CAST(w.pct AS DECIMAL(5,1))         AS pct_worked,
    CAST(d.pct AS DECIMAL(5,1))         AS pct_desire,
    CAST(d.pct - w.pct AS DECIMAL(5,1)) AS gap,
    CAST(d.pct / w.pct AS DECIMAL(5,2)) AS growth_ratio
FROM pct AS w
JOIN pct AS d ON w.skill = d.skill AND w.skill_group = d.skill_group
WHERE w.status = 'worked_with' AND d.status = 'desire_next_year'
  AND w.pct >= 5                       -- chỉ xét kỹ năng đủ phổ biến
ORDER BY gap DESC;

-- Q4b: Trong mỗi nhóm kinh nghiệm, bao nhiêu % muốn học Kubernetes năm tới?
SELECT
    r.exp_group,
    COUNT(*) AS so_nguoi_tra_loi,
    SUM(CASE WHEN k.respondent_id IS NOT NULL THEN 1 ELSE 0 END) AS so_muon_hoc,
    CAST(100.0 * SUM(CASE WHEN k.respondent_id IS NOT NULL THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,1)) AS pct_muon_hoc
FROM survey_respondents AS r
LEFT JOIN (
    SELECT DISTINCT respondent_id
    FROM survey_skills
    WHERE skill = 'Kubernetes' AND status = 'desire_next_year'
) AS k ON r.respondent_id = k.respondent_id
WHERE r.answered_platform_desire = 1      -- mẫu số: người có trả lời câu platform muốn dùng
  AND r.exp_group <> 'Unknown'
GROUP BY r.exp_group
ORDER BY CASE r.exp_group                 -- sắp nhóm kinh nghiệm theo thứ tự tăng dần
             WHEN '0-2 nam'     THEN 1
             WHEN '3-5 nam'     THEN 2
             WHEN '6-10 nam'    THEN 3
             WHEN '11-20 nam'   THEN 4
             WHEN 'Tren 20 nam' THEN 5
         END;
