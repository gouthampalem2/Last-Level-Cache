package my_pkg;

parameter SIZE_OF_ADDRESS = 32;
parameter SIZE_OF_EACH_CACHE_LINE = 64;
parameter CAPACITY = 2**24;
parameter NUMBER_OF_WAYS = 8;
//cache status
typedef enum bit {miss,hit} status;
//MESI states
typedef enum bit [1:0] {I,M,E,S}mesi_bits;
//cache line in each set
typedef struct packed{
mesi_bits state;
bit [10:0]tag_bits;} Line;
//cache set
typedef struct packed {
bit [6:0]PLRU;
Line [0:7] Way ;} set;
//cache line copy
typedef struct packed{
bit [31:0]addr;
mesi_bits state;
bit [10:0]tag_bits;} Line_copy;
//cache set copy
typedef struct packed{
bit [6:0]PLRU;
Line_copy [0:7] Way ;} set_copy;
endpackage
