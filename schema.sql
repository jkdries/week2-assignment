-- schema.sql: structure of library.db, a small home lending library
-- for friends and neighbors.
--
-- Build the database with:  sqlite3 library.db < schema.sql
--
-- SQLite has no separate date type, so dates are stored as text in
-- YYYY-MM-DD form. Each date column has a CHECK rule, "date(x) IS x", that
-- only accepts a real calendar date written exactly that way: SQLite's
-- date() function rewrites anything else (e.g. '2026-02-30' becomes
-- '2026-03-02', and '10/26/2026' becomes NULL), so the comparison fails.
-- IS is used instead of = because "NULL = x" is NULL, and a CHECK that
-- evaluates to NULL passes; "NULL IS x" is false, so the value is rejected.

PRAGMA foreign_keys = ON;

-- One row per title (a "work"), e.g. The Hobbit.
-- Author and contributor names are kept with the book, as printed on it.
CREATE TABLE books (
    book_id                   INTEGER PRIMARY KEY,
    source_book_id            INTEGER UNIQUE,          -- book_id in books.csv (Goodbooks-10k)
    title                     TEXT    NOT NULL,
    series                    TEXT,
    series_number             INTEGER,                 -- "volume number" within the series
    authors                   TEXT    NOT NULL,        -- one or more names, comma-separated
    contributors              TEXT,                    -- illustrators, translators, etc., with role
    original_title            TEXT,
    original_publication_year INTEGER,                 -- year first published; negative = BC
    isbn                      TEXT UNIQUE CHECK (length(isbn) = 10),
    isbn13                    TEXT UNIQUE CHECK (length(isbn13) = 13),
    language_code             TEXT,
    dewey_decimal             TEXT,                    -- e.g. '823.912'; blank until assigned
    cover_image_url           TEXT,
    CHECK (series_number IS NULL OR series IS NOT NULL)
);

-- One row per physical copy on the shelf, identified by its barcode label.
CREATE TABLE copies (
    barcode         TEXT    PRIMARY KEY,
    book_id         INTEGER NOT NULL REFERENCES books (book_id),
    acquired_date   TEXT    NOT NULL DEFAULT (date('now'))
                    CHECK (date(acquired_date) IS acquired_date),
    condition       TEXT    NOT NULL DEFAULT 'good'
                    CHECK (condition IN ('good', 'needs repair', 'lost', 'withdrawn')),
    condition_notes TEXT                                       -- free-text special notes
);

-- One row per person allowed to borrow.
CREATE TABLE members (
    member_id         INTEGER PRIMARY KEY,
    first_name        TEXT NOT NULL,
    middle_initial    TEXT CHECK (middle_initial IS NULL OR length(middle_initial) = 1),
    last_name         TEXT NOT NULL,
    street_address    TEXT,
    city              TEXT,
    state             TEXT,
    postal_code       TEXT,
    cell_phone        TEXT,
    email             TEXT UNIQUE,
    birthdate         TEXT CHECK (birthdate IS NULL OR date(birthdate) IS birthdate),
    membership_status TEXT NOT NULL DEFAULT 'active'
                      CHECK (membership_status IN ('active', 'suspended', 'inactive')),
    joined_date       TEXT NOT NULL DEFAULT (date('now'))
                      CHECK (date(joined_date) IS joined_date)
);

-- One row per checkout, current or past. A NULL returned_date means the copy is still out.
CREATE TABLE loans (
    loan_id       INTEGER PRIMARY KEY,
    barcode       TEXT    NOT NULL REFERENCES copies (barcode),
    member_id     INTEGER NOT NULL REFERENCES members (member_id),
    checkout_date TEXT    NOT NULL CHECK (date(checkout_date) IS checkout_date),
    due_date      TEXT    NOT NULL CHECK (date(due_date) IS due_date),
    returned_date TEXT             CHECK (returned_date IS NULL OR date(returned_date) IS returned_date),
                                                               -- returned_date is NULL while out
    CHECK (due_date >= checkout_date),
    CHECK (returned_date IS NULL OR returned_date >= checkout_date)
);

-- A copy can only be checked out to one person at a time.
CREATE UNIQUE INDEX one_open_loan_per_copy ON loans (barcode) WHERE returned_date IS NULL;

CREATE INDEX loans_by_member ON loans (member_id);
CREATE INDEX copies_by_book  ON copies (book_id);

-- Current status of every copy, worked out from its condition and its loans.
CREATE VIEW copy_status AS
SELECT c.barcode,
       b.title,
       b.authors,
       c.condition,
       l.member_id,
       l.due_date,
       CASE
           WHEN c.condition IN ('lost', 'withdrawn')  THEN c.condition
           WHEN l.loan_id IS NULL AND c.condition = 'needs repair' THEN 'needs repair'
           WHEN l.loan_id IS NULL                     THEN 'available'
           WHEN l.due_date < date('now')              THEN 'overdue'
           ELSE 'checked out'
       END AS status
FROM copies c
JOIN books b ON b.book_id = c.book_id
LEFT JOIN loans l ON l.barcode = c.barcode AND l.returned_date IS NULL;
