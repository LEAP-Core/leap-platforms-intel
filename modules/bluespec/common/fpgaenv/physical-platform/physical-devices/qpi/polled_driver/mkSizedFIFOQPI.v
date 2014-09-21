//
// Generated by Bluespec Compiler, version 2014.07.A (build 34078, 2014-07-30)
//
// On Thu Sep 18 17:48:38 EDT 2014
//
// BVI format method schedule info:
// schedule enq  CF ( deq, first );
// schedule enq  SBR ( clear );
// schedule enq  C ( enq );
//
// schedule deq  CF ( enq );
// schedule deq  SBR ( clear );
// schedule deq  C ( deq );
//
// schedule first  CF ( enq, first, notFull, notEmpty );
// schedule first  SB ( deq, clear );
//
// schedule notFull  CF ( first, notFull, notEmpty );
// schedule notFull  SB ( enq, deq, clear );
//
// schedule notEmpty  CF ( first, notFull, notEmpty );
// schedule notEmpty  SB ( enq, deq, clear );
//
// schedule clear  SBR ( clear );
//
//
// Ports:
// Name                         I/O  size props
// RDY_enq                        O     1 reg
// RDY_deq                        O     1 reg
// first                          O     1 reg
// RDY_first                      O     1 reg
// notFull                        O     1 reg
// RDY_notFull                    O     1 const
// notEmpty                       O     1 reg
// RDY_notEmpty                   O     1 const
// RDY_clear                      O     1 const
// CLK                            I     1 clock
// RST_N                          I     1 reset
// enq_1                          I     1 reg
// EN_enq                         I     1
// EN_deq                         I     1
// EN_clear                       I     1
//
// No combinational paths from inputs to outputs
//
//

`ifdef BSV_ASSIGNMENT_DELAY
`else
  `define BSV_ASSIGNMENT_DELAY
`endif

`ifdef BSV_POSITIVE_RESET
  `define BSV_RESET_VALUE 1'b1
  `define BSV_RESET_EDGE posedge
`else
  `define BSV_RESET_VALUE 1'b0
  `define BSV_RESET_EDGE negedge
`endif

module mkSizedFIFOQPI(CLK,
		      RST_N,

		      enq_1,
		      EN_enq,
		      RDY_enq,

		      EN_deq,
		      RDY_deq,

		      first,
		      RDY_first,

		      notFull,
		      RDY_notFull,

		      notEmpty,
		      RDY_notEmpty,

		      EN_clear,
		      RDY_clear);
  input  CLK;
  input  RST_N;

  // action method enq
  input  enq_1;
  input  EN_enq;
  output RDY_enq;

  // action method deq
  input  EN_deq;
  output RDY_deq;

  // value method first
  output first;
  output RDY_first;

  // value method notFull
  output notFull;
  output RDY_notFull;

  // value method notEmpty
  output notEmpty;
  output RDY_notEmpty;

  // action method clear
  input  EN_clear;
  output RDY_clear;

  // signals for module outputs
  wire RDY_clear,
       RDY_deq,
       RDY_enq,
       RDY_first,
       RDY_notEmpty,
       RDY_notFull,
       first,
       notEmpty,
       notFull;

  // ports of submodule m
  wire m_CLR, m_DEQ, m_D_IN, m_D_OUT, m_EMPTY_N, m_ENQ, m_FULL_N;

  // rule scheduling signals
  wire CAN_FIRE_clear,
       CAN_FIRE_deq,
       CAN_FIRE_enq,
       WILL_FIRE_clear,
       WILL_FIRE_deq,
       WILL_FIRE_enq;

  // action method enq
  assign RDY_enq = m_FULL_N ;
  assign CAN_FIRE_enq = m_FULL_N ;
  assign WILL_FIRE_enq = EN_enq ;

  // action method deq
  assign RDY_deq = m_EMPTY_N ;
  assign CAN_FIRE_deq = m_EMPTY_N ;
  assign WILL_FIRE_deq = EN_deq ;

  // value method first
  assign first = m_D_OUT ;
  assign RDY_first = m_EMPTY_N ;

  // value method notFull
  assign notFull = m_FULL_N ;
  assign RDY_notFull = 1'd1 ;

  // value method notEmpty
  assign notEmpty = m_EMPTY_N ;
  assign RDY_notEmpty = 1'd1 ;

  // action method clear
  assign RDY_clear = 1'd1 ;
  assign CAN_FIRE_clear = 1'd1 ;
  assign WILL_FIRE_clear = EN_clear ;

  // submodule m
  SizedFIFO #(.p1width(32'd1),
	      .p2depth(32'd64),
	      .p3cntr_width(32'd6),
	      .guarded(32'd1)) m(.RST(RST_N),
				 .CLK(CLK),
				 .D_IN(m_D_IN),
				 .ENQ(m_ENQ),
				 .DEQ(m_DEQ),
				 .CLR(m_CLR),
				 .D_OUT(m_D_OUT),
				 .FULL_N(m_FULL_N),
				 .EMPTY_N(m_EMPTY_N));

  // submodule m
  assign m_D_IN = enq_1 ;
  assign m_ENQ = EN_enq ;
  assign m_DEQ = EN_deq ;
  assign m_CLR = EN_clear ;
endmodule  // mkSizedFIFOQPI

