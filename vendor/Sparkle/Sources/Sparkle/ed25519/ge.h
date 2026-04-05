#ifndef GE_H
#define GE_H

#include "fe.h"


/*
ge means group element.

Here the group is the set of pairs (x,y) of field elements (see fe.h)
satisfying -x^2 + y^2 = 1 + d x^2y^2
where d = -121665/121666.

Representations:
  ge_p2 (projective): (X:Y:Z) satisfying x=X/Z, y=Y/Z
  ge_p3 (extended): (X:Y:Z:T) satisfying x=X/Z, y=Y/Z, XY=ZT
  ge_p1p1 (completed): ((X:Z),(Y:T)) satisfying x=X/Z, y=Y/T
  ge_precomp (Duif): (y+x,y-x,2dxy)
*/

typedef struct {
  fe X;
  fe Y;
  fe Z;
} ge_p2;

typedef struct {
  fe X;
  fe Y;
  fe Z;
  fe T;
} ge_p3;

typedef struct {
  fe X;
  fe Y;
  fe Z;
  fe T;
} ge_p1p1;

typedef struct {
  fe yplusx;
  fe yminusx;
  fe xy2d;
} ge_precomp;

typedef struct {
  fe YplusX;
  fe YminusX;
  fe Z;
  fe T2d;
} ge_cached;

void ge_p3_tobytes(unsigned char *s, const ge_p3 *h);
void ge_tobytes(unsigned char *s, const ge_p2 *h);
int ge_frombytes_negate_vartime(ge_p3 *h, const unsigned char *s);

void ge_add(ge_p1p1 *r, const ge_p3 *p, const ge_cached *q);
void ge_sub(ge_p1p1 *r, const ge_p3 *p, const ge_cached *q);
void ge_double_scalarmult_vartime(ge_p2 *r, const unsigned char *a, const ge_p3 *A, const unsigned char *b);
void ge_madd(ge_p1p1 *r, const ge_p3 *p, const ge_precomp *q);
void ge_msub(ge_p1p1 *r, const ge_p3 *p, const ge_precomp *q);
void ge_scalarmult_base(ge_p3 *h, const unsigned char *a);

void ge_p1p1_to_p2(ge_p2 *r, const ge_p1p1 *p);
void ge_p1p1_to_p3(ge_p3 *r, const ge_p1p1 *p);
void ge_p2_0(ge_p2 *h);
void ge_p2_dbl(ge_p1p1 *r, const ge_p2 *p);
void ge_p3_0(ge_p3 *h);
void ge_p3_dbl(ge_p1p1 *r, const ge_p3 *p);
void ge_p3_to_cached(ge_cached *r, const ge_p3 *p);
void ge_p3_to_p2(ge_p2 *r, const ge_p3 *p);

#endif
