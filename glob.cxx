/* glob.c -- wildcard matching ($Revision: 1.1.1.1 $) */

#define	REQUIRE_STAT	1
#define	REQUIRE_DIRENT	1

#include "es.hxx"
#include "term.hxx"

const char *QUOTED = "QUOTED", *UNQUOTED = "RAW";

/* hastilde -- true iff the first character is a ~ and it is not quoted */
static bool hastilde(const char *s, const char *q) {
	return *s == '~' && (q == UNQUOTED || *q == 'r');
}

/* haswild -- true iff some unquoted character is a wildcard character */
extern bool haswild(const char *s, const char *q) {
	if (q == QUOTED)
		return false;
	if (q == UNQUOTED)
		for (;;) {
			int c = *s++;
			if (c == '\0')
				return false;
			if (c == '*' || c == '?' || c == '[')
				return true;
		}
	for (;;) {
		int c = *s++, r = *q++;
		if (c == '\0')
			return false;
		if ((c == '*' || c == '?' || c == '[') && (r == 'r'))
			return true;
	}
}

/* ishiddenfile -- return ltrue if the file is a dot file to be hidden */
static int ishiddenfile(const char *s) {
#if SHOW_DOT_FILES
	return *s == '.' && (!s[1] || (s[1] == '.' && !s[2]));
#else
	return *s == '.';
#endif
}

/* dirmatch -- match a pattern against the contents of directory */
List* dirmatch(const char* prefix, 
	       const char* dirname,
	       const char* pattern, 
	       const char* quote) 
{
	static struct stat s;

	/*
	 * opendir succeeds on regular files on some systems, so the stat call
	 * is necessary (sigh);  the check is done here instead of with the
	 * opendir to handle a trailing slash.
	 */
	if (stat(dirname, &s) == -1 || (s.st_mode & S_IFMT) != S_IFDIR)
		return NULL;

	if (!haswild(pattern, quote)) {
		char *name = str("%s%s", prefix, pattern);
		if (lstat(name, &s) == -1)
			return NULL;
		return mklist(mkstr(name), NULL);
	}

	DIR *dirp = opendir(dirname);
	if (dirp == NULL)
		return NULL;

	List* list; 
	 /* The structure containing t->next could be forwarded, making prevp a bad pointer */
	List **prevp = &list;
	Dirent *dp;
	while ((dp = readdir(dirp)) != NULL)
		if (match(dp->d_name, pattern, quote)
		    && (!ishiddenfile(dp->d_name) || *pattern == '.')) {
			List *t = mklist(mkstr(str("%s%s",
						    prefix, dp->d_name)),
					  NULL);
			*prevp = t;
			prevp = &t->next;
			assert (t->next == NULL);
		}
	closedir(dirp);
	
	return list;
}

/* listglob -- glob a directory plus a filename pattern into a list of names */
static List* listglob(List* list, char *pattern, char *quote, size_t slashcount) {
	List* result; 
	List **prevp;
	

	for (prevp = &result; 
			list != NULL; 
			list = list->next) {
		static char *prefix = NULL;
		static size_t prefixlen = 0;

		assert(list->term != NULL);
		assert(!isclosure(list->term));

		const char* dir = getstr(list->term);
		size_t dirlen = strlen(dir);
		if (dirlen + slashcount + 1 >= prefixlen) {
			prefixlen = dirlen + slashcount + 1;
			prefix = reinterpret_cast<char*>(
					erealloc(prefix, prefixlen));
		}
		memcpy(prefix, dir, dirlen);
		memset(prefix + dirlen, '/', slashcount);
		prefix[dirlen + slashcount] = '\0';

		*prevp = dirmatch(prefix, dir, pattern, quote);
		while (*prevp != NULL)
			prevp = &(*prevp)->next;
	}
	
	return result;
}

/* glob1 -- glob pattern path against the file system */
static List* glob1(const char* pattern, const char* quote) {
	size_t psize;
	static char *dir = NULL, *pat = NULL, *qdir = NULL, *qpat = NULL, *raw = NULL;
	static size_t dsize = 0;

	assert(quote != QUOTED);

	if ((psize = strlen(pattern) + 1) > dsize || pat == NULL) {
		pat = reinterpret_cast<char*>(erealloc(pat, psize));
		raw = reinterpret_cast<char*>(erealloc(raw, psize));
		dir = reinterpret_cast<char*>(erealloc(dir, psize));
		qpat = reinterpret_cast<char*>(erealloc(qpat, psize));
		qdir = reinterpret_cast<char*>(erealloc(qdir, psize));
		dsize = psize;
		memset(raw, 'r', psize);
	}

	char *d, *p, *qd, *qp;
	d = dir;
	qd = qdir;
	
	const char *q = (quote == UNQUOTED) ? raw : quote;
	const char *s = pattern;
	if (*s == '/')
		while (*s == '/')
			*d++ = *s++, *qd++ = *q++;
	else
		while (*s != '/' && *s != '\0')
			*d++ = *s++, *qd++ = *q++; /* get first directory component */
	*d = '\0';

	/*
	 * Special case: no slashes in the pattern, i.e., open the current directory.
	 * Remember that w cannot consist of slashes alone (the other way *s could be
	 * zero) since doglob gets called iff there's a metacharacter to be matched
	 */
	if (*s == '\0') {
		
		return dirmatch("", ".", dir, qdir);
	}

	List* matched = (*pattern == '/')
			? mklist(mkstr(dir), NULL)
			: dirmatch("", ".", dir, qdir);
	do {
		size_t slashcount;
		SIGCHK();
		for (slashcount = 0; *s == '/'; s++, q++)
			slashcount++; /* skip slashes */
		for (p = pat, qp = qpat; *s != '/' && *s != '\0';)
			*p++ = *s++, *qp++ = *q++; /* get pat */
		*p = '\0';
		matched = listglob(matched, pat, qpat, slashcount);
	} while (*s != '\0' && matched != NULL);

	
	return matched;
}

/* glob0 -- glob a list, (destructively) passing through entries we don't care about */
static List* glob0(List* list, StrList* quote) {
	List* result; 
	List* expand1;
	List **prevp;
	

	for (result = NULL, prevp = &result; list != NULL;
	     list = list->next, quote = quote->next) {
		const char* str;
		if (
			quote->str == QUOTED
			|| !haswild((str = getstr(list->term)), quote->str)
		) {
			*prevp = list;
			prevp = &list->next;
		} else if ((expand1 = glob1(str, quote->str)) == NULL) {
			list->term->str = ""; 
			*prevp = list;
			prevp = &list->next;			
		} else {
			assert (expand1);
			assert (length(expand1) >= 1);
			*prevp = sortlist(expand1);
			while (*prevp != NULL)
				prevp = &(*prevp)->next;
		}
	}
	
	return result;
}

/* expandhome -- do tilde expansion by calling fn %home */
static char *expandhome(char* string, StrList* quote) {
	size_t slash;
	List* fn = varlookup("fn-%home", NULL);

	assert(*string == '~');
	assert(quote->str == UNQUOTED || *quote->str == 'r');

	if (fn == NULL) return string;
	
	int c;
	for (slash = 1; (c = string[slash]) != '/' && c != '\0'; slash++)
		;

	List* list = NULL;
	if (slash > 1)
		list = mklist(mkstr(gcndup(string + 1, slash - 1)), NULL);

	list = eval(append(fn, list), NULL, 0);

	if (list != NULL) {
		if (list->next != NULL)
			fail("es:expandhome", "%%home returned more than one value");
		char* home = gcdup(getstr(list->term));
		if (c == '\0') {
			string = home;
			quote->str = QUOTED;
		} else {
			size_t pathlen = strlen(string);
			size_t homelen = strlen(home);
			size_t len = pathlen - slash + homelen;
			{
				char* t = reinterpret_cast<char*>(GC_MALLOC(len + 1));
				memcpy(t, home, homelen);
				memcpy(&t[homelen], &string[slash], pathlen - slash);
				t[len] = '\0';
				string = t;
			}
			if (quote->str == UNQUOTED) {
				char *q = reinterpret_cast<char*>(GC_MALLOC(len + 1));
				memset(q, 'q', homelen);
				memset(&q[homelen], 'r', pathlen - slash);
				q[len] = '\0';
				quote->str = q;
			} else if (strchr(quote->str, 'r') == NULL)
				quote->str = QUOTED;
			else {
				char *q = reinterpret_cast<char*>(GC_MALLOC(len + 1));
				memset(q, 'q', homelen);
				memcpy(&q[homelen], &quote->str[slash], pathlen - slash);
				q[len] = '\0';
				quote->str = q;
			}
		}
	}
	return string;
}

/* glob -- globbing prepass (glob if we need to, and dispatch for tilde expansion) */
extern List* glob(List* list, StrList* quote) {
	List* lp;
	StrList* qp;
	bool doglobbing = false;

	for (lp = list, qp = quote; lp; lp = lp->next, qp = qp->next)
		if (qp->str != QUOTED) {
			assert(lp->term != NULL);
			assert(!isclosure(lp->term));
			char* str = gcdup(getstr(lp->term));
			assert(qp->str == UNQUOTED || \
			       strlen(qp->str) == strlen(str));
			if (hastilde(str, qp->str)) {
				str = expandhome(str, qp);
				/* Safety against forwarding of lp */
				Term *t = mkstr(str);
				lp->term = t;
			}
			if (haswild(str, qp->str))
				doglobbing = true;
			lp->term->str = str;
		}

	if (!doglobbing) return list;
	list = glob0(list, quote);
	return list;
}
