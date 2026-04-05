#include "ed25519.h"
#include "ge.h"
#include "sc.h"
#include "sha512.h"


/* see http://crypto.stackexchange.com/a/6215/4697 */
void ed25519_add_scalar(unsigned char *public_key, unsigned char *private_key, const unsigned char *scalar) {
    const unsigned char SC_1[32] = {1}; /* scalar with value 1 */
    
    unsigned char n[32]; 
    ge_p3 nB;
    ge_p1p1 A_p1p1;
    ge_p3 A;
    ge_p3 public_key_unpacked;
    ge_cached T;

    sha512_context hash;
    unsigned char hashbuf[64];

    int i;

    /* copy the scalar and clear highest bit */
    for (i = 0; i < 31; ++i) {
        n[i] = scalar[i];
    }
    n[31] = scalar[31] & 127;

    /* private key: a = n + t */
    if (private_key) {
        sc_muladd(private_key, SC_1, n, private_key);

        // https://github.com/orlp/ed25519/issues/3
        sha512_init(&hash);
        sha512_update(&hash, private_key + 32, 32);
        sha512_update(&hash, scalar, 32);
        sha512_final(&hash, hashbuf);
        for (i = 0; i < 32; ++i) {
            private_key[32 + i] = hashbuf[i];
        }
    }

    /* public key: A = nB + T */
    if (public_key) {
        /* if we know the private key we don't need a point addition, which is faster */
        /* using a "timing attack" you could find out wether or not we know the private
           key, but this information seems rather useless - if this is important pass
           public_key and private_key seperately in 2 function calls */
        if (private_key) {
            ge_scalarmult_base(&A, private_key);
        } else {
            /* unpack public key into T */
            ge_frombytes_negate_vartime(&public_key_unpacked, public_key);
            fe_neg(public_key_unpacked.X, public_key_unpacked.X); /* undo negate */
            fe_neg(public_key_unpacked.T, public_key_unpacked.T); /* undo negate */
            ge_p3_to_cached(&T, &public_key_unpacked);

            /* calculate n*B */
            ge_scalarmult_base(&nB, n);

            /* A = n*B + T */
            ge_add(&A_p1p1, &nB, &T);
            ge_p1p1_to_p3(&A, &A_p1p1);
        }
            
        /* pack public key */
        ge_p3_tobytes(public_key, &A);
    }
}
