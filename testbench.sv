`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

class transaction extends uvm_sequence_item;
  rand bit din;
  bit dout;
  
  function new(string path = "transaction");
    super.new(path);
  endfunction
  
  `uvm_object_utils_begin(transaction)
  `uvm_field_int(din,UVM_DEFAULT)
  `uvm_field_int(dout,UVM_DEFAULT)
  `uvm_object_utils_end
  
endclass

//////////////////////////////////////////////////////////

class generator extends uvm_sequence#(transaction);
  
  `uvm_object_utils(generator)
  
  transaction t_g;
  
  function new(string path = "generator");
    super.new(path);
  endfunction
  
  virtual task body();
    t_g = transaction::type_id::create("t_g");
    repeat(10) begin;
      start_item(t_g);
      assert(t_g.randomize());
      //`uvm_info("GEN",$sformatf("data din = %0d is sent to driver.....",t_g.din),UVM_NONE)
      finish_item(t_g);
      `uvm_info("GEN",$sformatf("data din = %0d is sent to driver.....",t_g.din),UVM_NONE)
    end
  endtask
  
endclass

//////////////////////////////////////////////////////

class driver extends uvm_driver#(transaction);
  `uvm_component_utils(driver)
  
  transaction t_d;
  virtual dff_if dif;
  
  function new(string path = "driver", uvm_component parent = null);
    super.new(path,parent);
  endfunction
  
  task reset();
    dif.rst <= 1'b1;
    dif.din <= 0;
    repeat(5)@(posedge dif.clk);
    dif.rst<= 1'b0;
    `uvm_info("DRV","Reset done",UVM_NONE)
  endtask
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t_d = transaction::type_id::create("t_d");
    
    if(!uvm_config_db#(virtual dff_if)::get(this,"","dif",dif))
      `uvm_error("DRV","unable to recieve config_db")
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    reset();
    forever begin
    seq_item_port.get_next_item(t_d);
    dif.din<= t_d.din;
    seq_item_port.item_done();
      `uvm_info("DRV",$sformatf("data din = %0d is sent to driver.....",t_d.din),UVM_NONE)
      repeat(2)@(posedge dif.clk);
    end
  endtask
  
endclass
    
////////////////////////////////////////////////
    
class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  uvm_analysis_port#(transaction) send;
  transaction t_m;
  virtual dff_if dif;
  
  function new(string path = "monitor", uvm_component parent = null);
    super.new(path, parent);
    send = new("write", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t_m = transaction::type_id::create("t_m");
    
    if(!uvm_config_db#(virtual dff_if)::get(this,"","dif",dif))
      `uvm_error("MON","unable to recieve config_db")
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    @(negedge dif.rst);
    forever begin
      repeat(2)@(posedge dif.clk);
      t_m.din = dif.din;
      t_m.dout = dif.dout;
      `uvm_info("MON",$sformatf("data din = %0d is send to scoreboard",t_m.din),UVM_NONE)
      //@(posedge dif.clk);
      send.write(t_m);
    end
  endtask
  
endclass
    
/////////////////////////////////////////////////////    

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  uvm_analysis_imp#(transaction,scoreboard) recv;
  transaction t_s;
  
  function new(string path = "scoreboard", uvm_component parent = null);
    super.new(path, parent);
    recv = new("recv",this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t_s = transaction::type_id::create("t_s");
  endfunction
  
  virtual function void write (transaction t);
    t_s = t;
    if(t_s.din == t_s.dout)
       `uvm_info("SCO","Data Matched",UVM_NONE)
    
    else
       `uvm_info("SCO","Test Failed",UVM_NONE)
    
  endfunction
  
endclass
      
/////////////////////////////////////////////////////      
      
class agent extends uvm_agent;
  `uvm_component_utils(agent);
  
  monitor m;
  driver d;
  uvm_sequencer#(transaction) seqr;
  
  function new(string path = "agent", uvm_component c);
    super.new(path, c);
  endfunction
  
  virtual function void build_phase (uvm_phase phase);
    super.build_phase(phase);
    m = monitor::type_id::create("m",this);
    d = driver::type_id::create("d",this);
    seqr = uvm_sequencer#(transaction)::type_id::create("seqr",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
    
/////////////////////////////////////////////////////////    
    
class env extends uvm_env;
  `uvm_component_utils(env)
  
  agent a;
  scoreboard s;
  
  function new(string path = "env", uvm_component c);
    super.new(path,c);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a = agent::type_id::create("a",this);
    s = scoreboard::type_id::create("s",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.m.send.connect(s.recv);
  endfunction
  
endclass
    
////////////////////////////////////////////////////////    
    
class test extends uvm_test;
  `uvm_component_utils(test)
  
  env e;
  generator g;
  
  function new(string path = "env", uvm_component c);
    super.new(path,c);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e = env::type_id::create("e",this);
    g = generator::type_id::create("g",this); 
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    g.start(e.a.seqr);
    #60
    phase.drop_objection(this);
    
  endtask
endclass
    
///////////////////////////////////////////////////////    
    
module tb;
  dff_if dif();
  
  dff dut(.din(dif.din),.dout(dif.dout),.clk(dif.clk),.rst(dif.rst));
  
  initial begin
    dif.rst = 1'b0;
    dif.clk = 1'b0;
  end
  
  always#10 dif.clk = ~dif.clk;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
  initial begin
    uvm_config_db#(virtual dff_if)::set(null,"*","dif",dif);
    run_test("test");
  end
  
endmodule