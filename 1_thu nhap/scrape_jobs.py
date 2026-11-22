"""
scrape_jobs.py
Giai đoạn 1 - Thu thập dữ liệu: cào tin tuyển dụng IT (Job postings)
Công cụ: Requests + BeautifulSoup + Pandas

Cách chạy:
    pip install requests beautifulsoup4 pandas lxml
    python scrape_jobs.py check URL1 URL2 ...  # B0: thử nhiều trang, xem trang nào cào được
    python scrape_jobs.py discover   # B1: xem trang danh sách có link tin nào
    python scrape_jobs.py scrape     # B2: cào toàn bộ và lưu CSV

Đầu ra:
    jobs_raw.csv      - 1 dòng / 1 tin tuyển dụng (kèm kỹ năng đã tách)
    job_skills.csv    - dạng "dài": 1 dòng / (tin, kỹ năng) để dễ đếm tần suất
"""

import re
import sys
import time
import random
from urllib import robotparser
from urllib.parse import urljoin, urlparse

import requests
import pandas as pd
from bs4 import BeautifulSoup

# ============================================================
# 1. CẤU HÌNH  (CHỈNH PHẦN NÀY CHO KHỚP TRANG BẠN CHỌN)
# ============================================================
BASE_URL = "https://itviec.com"                      # TODO: đổi sang trang bạn chọn
LIST_URL = BASE_URL + "/it-jobs?page={page}"         # TODO: mở trình duyệt, bấm sang trang 2 để xem mẫu URL
MAX_PAGES = 30                                       # số trang danh sách tối đa
JOB_LINK_REGEX = r"/it-jobs/[\w\-]+"                 # TODO: regex nhận diện link TIN CHI TIẾT (xem bằng 'discover')
DELAY = (2, 4)                                       # nghỉ ngẫu nhiên 2-4 giây giữa các request (lịch sự với server)

# Selector CSS cho trang chi tiết. Để None thì script tự dùng phương án dự phòng.
# TODO: chuột phải -> Inspect trên một tin để lấy selector đúng.
SELECTORS = {
    "title": "h1",
    "company": None,
    "location": None,
    "description": None,   # nếu None sẽ lấy <main>/<article>, cuối cùng mới tới toàn trang
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; VTI-Academy-StudentProject/1.0)",
    "Accept-Language": "vi,en;q=0.8",
}

# ============================================================
# 2. TỪ ĐIỂN KỸ NĂNG  (chuẩn hóa tên: nhiều cách viết -> 1 tên chuẩn)
#    Tên chuẩn khớp với cách gọi trong khảo sát Stack Overflow
#    để sau này ghép 2 nguồn.
# ============================================================
SKILLS = {
    "language": {
        "JavaScript": ["javascript", "node.js", "nodejs"],
        "TypeScript": ["typescript"],
        "Python": ["python"],
        "Java": ["java"],
        "C#": ["c#", "csharp"],
        "C++": ["c++"],
        "PHP": ["php"],
        "Go": ["golang"],
        "Kotlin": ["kotlin"],
        "Swift": ["swift"],
        "Ruby": ["ruby"],
        "Rust": ["rust"],
        "SQL": ["sql", "t-sql", "pl/sql"],
        "HTML/CSS": ["html", "css", "html5", "css3"],
        "Bash/Shell": ["bash", "shell script"],
        "R": ["rstudio"],  # "R" đứng một mình quá mơ hồ nên chỉ bắt qua RStudio
    },
    "database": {
        "MySQL": ["mysql"],
        "PostgreSQL": ["postgresql", "postgres"],
        "SQL Server": ["sql server", "mssql", "ms sql"],
        "Oracle": ["oracle"],
        "MongoDB": ["mongodb", "mongo"],
        "Redis": ["redis"],
        "SQLite": ["sqlite"],
        "Elasticsearch": ["elasticsearch"],
        "Cassandra": ["cassandra"],
        "MariaDB": ["mariadb"],
    },
    "framework": {
        "React": ["react", "reactjs", "react.js"],
        "Angular": ["angular", "angularjs"],
        "Vue.js": ["vue", "vuejs", "vue.js"],
        "Spring": ["spring boot", "spring"],
        "Django": ["django"],
        "Flask": ["flask"],
        "ASP.NET": ["asp.net"],
        ".NET": [".net", "dotnet", ".net core"],
        "Laravel": ["laravel"],
        "Express": ["expressjs", "express.js"],
        "Pandas": ["pandas"],
        "TensorFlow": ["tensorflow"],
        "PyTorch": ["pytorch"],
    },
    "platform_tool": {
        "AWS": ["aws", "amazon web services"],
        "Azure": ["azure"],
        "Google Cloud": ["gcp", "google cloud"],
        "Docker": ["docker"],
        "Kubernetes": ["kubernetes", "k8s"],
        "Linux": ["linux"],
        "Git": ["git", "github", "gitlab"],
        "Jira": ["jira"],
        "Power BI": ["power bi", "powerbi"],
        "Tableau": ["tableau"],
        "Android": ["android"],
        "iOS": ["ios"],
    },
}


def build_patterns():
    """Biên dịch regex cho từng bí danh. Lookaround giúp 'java' KHÔNG khớp trong 'javascript',
    'sql' KHÔNG khớp trong 'mysql'."""
    patterns = []
    for group, mapping in SKILLS.items():
        for canonical, aliases in mapping.items():
            for alias in aliases:
                rx = re.compile(
                    r"(?<![A-Za-z0-9+#.])" + re.escape(alias) + r"(?![A-Za-z0-9+#])",
                    flags=re.IGNORECASE,
                )
                patterns.append((group, canonical, rx))
    return patterns


PATTERNS = build_patterns()


def extract_skills(text):
    """Trả về dict {nhóm: [tên kỹ năng chuẩn,...]} tìm thấy trong văn bản (không trùng)."""
    found = {g: set() for g in SKILLS}
    for group, canonical, rx in PATTERNS:
        if rx.search(text):
            found[group].add(canonical)
    return {g: sorted(v) for g, v in found.items()}


# ============================================================
# 3. HÀM TIỆN ÍCH CHO VIỆC CÀO
# ============================================================
session = requests.Session()
session.headers.update(HEADERS)


def allowed_by_robots(url):
    """Kiểm tra robots.txt xem có được phép cào URL này không."""
    rp = robotparser.RobotFileParser()
    rp.set_url(urljoin(BASE_URL, "/robots.txt"))
    try:
        rp.read()
        return rp.can_fetch(HEADERS["User-Agent"], url)
    except Exception:
        return True  # không đọc được robots.txt thì mặc định thử, nhưng vẫn giữ delay


def get_html(url):
    """Tải 1 trang, nghỉ ngẫu nhiên sau mỗi request. Trả về None nếu lỗi/bị chặn."""
    try:
        resp = session.get(url, timeout=20)
    except requests.RequestException as e:
        print(f"  [LỖI mạng] {url}: {e}")
        return None
    time.sleep(random.uniform(*DELAY))
    if resp.status_code != 200:
        print(f"  [HTTP {resp.status_code}] {url}")  # 403/429 = bị chặn bot
        return None
    return resp.text


def select_text(soup, selector):
    """Lấy text theo selector CSS, không có thì trả chuỗi rỗng."""
    if not selector:
        return ""
    el = soup.select_one(selector)
    return el.get_text(" ", strip=True) if el else ""


def get_description(soup):
    """Phần mô tả công việc: ưu tiên selector, rồi <main>/<article>, cuối cùng toàn trang."""
    text = select_text(soup, SELECTORS["description"])
    if text:
        return text
    for tag in ("main", "article"):
        el = soup.find(tag)
        if el:
            return el.get_text(" ", strip=True)
    return soup.get_text(" ", strip=True)


def collect_job_links(max_pages):
    """Duyệt các trang danh sách, gom link tin chi tiết (không trùng)."""
    links = []
    seen = set()
    link_rx = re.compile(JOB_LINK_REGEX)
    for page in range(1, max_pages + 1):
        url = LIST_URL.format(page=page)
        print(f"Trang danh sách {page}: {url}")
        html = get_html(url)
        if html is None:
            break  # bị chặn hoặc hết trang -> dừng
        soup = BeautifulSoup(html, "lxml")
        new = 0
        for a in soup.find_all("a", href=True):
            full = urljoin(BASE_URL, a["href"]).split("?")[0]
            if link_rx.search(urlparse(full).path) and full not in seen:
                seen.add(full)
                links.append(full)
                new += 1
        print(f"  +{new} link mới (tổng {len(links)})")
        if new == 0:
            break  # trang không còn tin mới
    return links


# ============================================================
# 4. HAI CHẾ ĐỘ CHẠY
# ============================================================
def discover():
    """Chế độ dò: in ra các link trên trang danh sách đầu tiên để bạn chỉnh JOB_LINK_REGEX."""
    html = get_html(LIST_URL.format(page=1))
    if html is None:
        print("Không tải được trang. Xem phần 'Nếu bị chặn' ở cuối file.")
        return
    soup = BeautifulSoup(html, "lxml")
    hrefs = sorted({urljoin(BASE_URL, a["href"]).split("?")[0] for a in soup.find_all("a", href=True)})
    print(f"Có {len(hrefs)} link. 40 link đầu:")
    for h in hrefs[:40]:
        print(" ", h)


def scrape():
    """Chế độ cào: danh sách -> chi tiết -> tách kỹ năng -> lưu CSV."""
    if not allowed_by_robots(LIST_URL.format(page=1)):
        print("robots.txt KHÔNG cho phép cào trang này. Hãy chọn nguồn khác.")
        return

    links = collect_job_links(MAX_PAGES)
    print(f"\nTổng {len(links)} tin cần cào chi tiết.\n")

    rows, long_rows = [], []
    for i, url in enumerate(links, 1):
        html = get_html(url)
        if html is None:
            continue
        soup = BeautifulSoup(html, "lxml")
        title = select_text(soup, SELECTORS["title"])
        company = select_text(soup, SELECTORS["company"])
        location = select_text(soup, SELECTORS["location"])
        desc = get_description(soup)

        # Tách kỹ năng từ tiêu đề + mô tả
        skills = extract_skills(f"{title} {desc}")
        rows.append({
            "job_url": url,
            "job_title": title,
            "company": company,
            "location": location,
            "language_list": ";".join(skills["language"]),         # cùng định dạng ';' như khảo sát
            "database_list": ";".join(skills["database"]),
            "framework_list": ";".join(skills["framework"]),
            "platform_tool_list": ";".join(skills["platform_tool"]),
            "description_length": len(desc),
        })
        for group, names in skills.items():
            for name in names:
                long_rows.append({"job_url": url, "skill_group": group, "skill": name})

        if i % 25 == 0:
            print(f"  đã cào {i}/{len(links)} tin")
            pd.DataFrame(rows).to_csv("jobs_raw.csv", index=False, encoding="utf-8-sig")  # lưu tạm

    df = pd.DataFrame(rows).drop_duplicates(subset="job_url")
    df.to_csv("jobs_raw.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(long_rows).to_csv("job_skills.csv", index=False, encoding="utf-8-sig")
    print(f"\nXong: {len(df)} tin -> jobs_raw.csv, {len(long_rows)} dòng kỹ năng -> job_skills.csv")


def check(urls):
    """Chế độ kiểm tra: thử nhiều URL, báo trang nào cào được bằng Requests.
    Cách dùng: python scrape_jobs.py check <url1> <url2> ...
    Với mỗi URL in ra: robots.txt có cho phép không, mã HTTP, số link <a> trong HTML gốc,
    và dấu hiệu bị chặn bot (Cloudflare) hoặc nội dung do JavaScript tạo ra."""
    for url in urls:
        parts = urlparse(url)
        origin = f"{parts.scheme}://{parts.netloc}"

        # 1) robots.txt
        rp = robotparser.RobotFileParser()
        rp.set_url(origin + "/robots.txt")
        try:
            rp.read()
            robots_ok = rp.can_fetch(HEADERS["User-Agent"], url)
        except Exception:
            robots_ok = None  # không đọc được

        # 2) Tải thử trang
        try:
            resp = session.get(url, timeout=20)
        except requests.RequestException as e:
            print(f"\n{url}\n  KHÔNG KẾT NỐI ĐƯỢC: {e}")
            continue

        soup = BeautifulSoup(resp.text, "lxml")
        n_links = len(soup.find_all("a", href=True))
        blocked = any(k in resp.text.lower() for k in ("just a moment", "cf-chl", "captcha", "access denied"))

        # 3) Kết luận
        if resp.status_code != 200 or blocked:
            verdict = "BỊ CHẶN -> bỏ trang này"
        elif robots_ok is False:
            verdict = "robots.txt KHÔNG cho phép -> bỏ trang này"
        elif n_links < 30:
            verdict = "ít link, có thể nội dung do JavaScript tạo -> cần Playwright/Selenium"
        else:
            verdict = "OK -> có thể thử cào bằng Requests"
        print(f"\n{url}\n  HTTP {resp.status_code} | robots: {robots_ok} | {n_links} link | {verdict}")
        time.sleep(random.uniform(*DELAY))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "discover"
    if mode == "check":
        check(sys.argv[2:])
    else:
        {"discover": discover, "scrape": scrape}.get(mode, discover)()

# ------------------------------------------------------------
# NẾU BỊ CHẶN (HTTP 403/429 hoặc trang trống):
#  - Nhiều trang tuyển dụng dùng Cloudflare hoặc tải nội dung bằng JavaScript,
#    nên Requests không lấy được. Thử trang khác trong cùng danh sách.
#  - Hoặc dùng Playwright/Selenium để mở trang như trình duyệt thật.
#  - Phương án dự phòng: chuyển sang cổng đào tạo (training portals), đề cho phép.
# ------------------------------------------------------------
