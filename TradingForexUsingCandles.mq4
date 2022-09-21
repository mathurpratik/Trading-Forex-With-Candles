//+------------------------------------------------------------------+
//|                  Pratik Mathur                                   |
//|                  mathurpratik@gmail.com                          |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011, MetaQuotes Software Corp."
#property link      "http://www.metaquotes.net"
#include <stdlib.mqh>
#include <WinUser32.mqh>
// user-modifiable variables
extern int MAX_ALLOWED_STOP_LOSSES = 5;
extern double INITIAL_LOTS = 5;
extern double SECOND_ENTRY_MULTIPLE=1;
extern double THIRD_ENTRY_MULTIPLE=2;
extern double FOURTH_ENTRY_MULTIPLE=3;
extern double FIFTH_ENTRY_MULTIPLE=5;
extern int MAX_ALLOWED_SLIPPAGE = 3;
extern int TAKE_PROFIT = 20; 
extern int SEC_THIR_FORTH_TP = 20;
extern int MAGIC_NUMBER = 20850;
extern double FIRST_ENTRY_SL_CONSTANT = 1;
extern double SECOND_THIRD_ENTRY_SL_CONSTANT=1;
extern double MAX_ENTRY_SIZE=40;
extern double MIN_STOP_DISTANCE = 0.0003;
extern int MIN_STOP_HOUR=-1; // 12PM: stop trading
extern int MAX_STOP_HOUR=-1; // 23:59: start trading at 00:00

//+------------------------------------------------------------------+
//| global variables  - set by user                                  |
//+------------------------------------------------------------------+
 datetime currentCandleTimestamp;   // will be used to determine when new candle comes in
 int numOfStopLosses = 0;           // total number of stop losses
 double totalPipsLost   = 0;           // total number of pips lost
 double numPipsLost = 0;
 int totalMarketOrders=0;   
 double myPoint = 0.0001;
 bool tpBuyCandle=false;
 bool tpSellCandle=false;
 bool slBuyCandle=false;
 bool slSellCandle=false;
 double nextEntrySize=-1;
 bool didHandleStopLoss=false;
 
 //bool expertOn=true;
//+------------------------------------------------------------------+
//| Holds information about current open order                       |
//+------------------------------------------------------------------+
 int currOrderTicket = -1;         // ticket # for opened order (use OrderTicket())
 datetime currOrderTimeSent;       // time the current (open) order was opened
 int currOrderType   = -1;         // (OP_BUY or OP_SELL or -1) (use OrderType())
 double currOrderStopLoss   =-1;   // SL for an opened order (use OrderStopLoss())
 double currOrderTakeProfit =-1;   // TP for an opened order (use OrderTakeProfit())
 double currOrderPrice = -1;       // price of opened order (use OrderOpenPrice())
 int currOrderLots = -1;
 int currOCOTicket = -1;
//+------------------------------------------------------------------+
//| global variables  - constants                                    |
//+------------------------------------------------------------------+
string INITIAL_COMMENT = "TA";
string BUY_COMMENT = "-BUY";
string SELL_COMMENT = "-SELL";
string SL_COMMENT = "[sl]";
string TP_COMMENT = "[tp]";
string BUY_SL_COMMENT = "";
string SELL_SL_COMMENT = "";

datetime lastOrderTimeSent;       // time the original buy or sell order was sent/opened (useOrderOpenTime())
int lastOrderTicket=-1;
//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
  {
//----
   BUY_SL_COMMENT = StringConcatenate(INITIAL_COMMENT,BUY_COMMENT,SL_COMMENT);
   SELL_SL_COMMENT = StringConcatenate(INITIAL_COMMENT,SELL_COMMENT,SL_COMMENT);
   nextEntrySize=INITIAL_LOTS;
   Print("Starting Expert Advisor for first time.");
   Print("Account Balance: ", AccountBalance());
   updateOrderAccounting();
   
   if(MIN_STOP_HOUR != -1 && MAX_STOP_HOUR != -1){
   // if current time after 4pm or before 12 midnight
      if (localtimeIsBetweenRange(MIN_STOP_HOUR,MAX_STOP_HOUR)){
         // if no existing order
         if (currOrderTicket == -1){
      
            // no trading occurs from 4pm to 12 midnight!
            return(0);
         }
      }
   }
   // update current candle's time stamp
   currentCandleTimestamp = iTime(NULL,0,0);
   placeOrUpdateMarketOrder(false);
   return(0);
  }
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
  {
//----
   
//----
   return(0);
  }
//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
{
   updateOrderAccounting();
   
   if(MIN_STOP_HOUR != -1 && MAX_STOP_HOUR != -1){
   // if current time after 4pm or before 12 midnight
      if (localtimeIsBetweenRange(MIN_STOP_HOUR,MAX_STOP_HOUR)){
         // if no existing order
         if (currOrderTicket == -1){
      
            // no trading occurs from 4pm to 12 midnight!
            return(0);
         }
      }
   }
   // new reference candle
   if (currentCandleTimestamp != iTime(NULL,0,0)){
      Print("New Candle!");
      currentCandleTimestamp = iTime(NULL,0,0);
      
      tpBuyCandle=false;
      tpSellCandle=false;
      slBuyCandle =false;
      slSellCandle=false;
      // update existing order (if one exists) with new stop loss (i.e. low or high of reference candle)
      placeOrUpdateMarketOrder(true);  
   }
   else{
      placeOrUpdateMarketOrder(false);
   }
 
   return(0);
}

void placeOrUpdateMarketOrder(bool newCandle){
   RefreshRates();
   
   // check for stop losses first
   if (!didHandleStopLoss){
      int stopLossEncountered = stopLossHit();
      if (stopLossEncountered >= 0){
         // prepares next entry size to make up for loss
         handleStopLoss(stopLossEncountered);
         didHandleStopLoss = true;
      }
   }  
   if (buyCondition() && slBuyCandle == false){ // if we can BUY and we have not lost $$ on a BUY this candle period
      
      // if new candle this tick
      if (newCandle){
      
         // if open buy entry
         if (currOrderTicket != -1 && currOrderType == OP_BUY) { // if current open order is BUY
            Print("Update BUY!");
            PrintABHL();
            
            // update it with new stop loss
            myOrderModify(currOrderTicket, OP_BUY, 1,true);
            
         } // end update BUY Order
      }
      
      // if no open orders and no take profit on buy entry this candle
      else if (currOrderTicket == -1 && tpBuyCandle==false) { 
         RefreshRates();
         PrintABHL();
         
         if (numOfStopLosses == 0){
            Print("sending 1st entry order BUY");
         }
         else if (numOfStopLosses == 1){
            Print("sending 2st entry order BUY");
         }
         else if (numOfStopLosses == 2){
            Print("sending 3rd entry order BUY");
         }
         else if (numOfStopLosses == 3){
            Print("sending 4th entry order BUY");
         }
         else if (numOfStopLosses == 4){
            Print("sending 5th entry order BUY");
         }
         else{
            Print("THIS SHOULD NOT HAPPEN. ABOUT TO SEND A 6TH ENTRY ORDER!!");
         }
         
         Print("entry size = ", nextEntrySize);
         myOrderSend(OP_BUY, nextEntrySize);
         didHandleStopLoss = false;
      }
   }
      
   else if(sellCondition() && slSellCandle == false){ // if we can SELL and we have not lost $$ on a SELL this candle period
      
      
      if (newCandle){
         if (currOrderTicket != -1 && currOrderType == OP_SELL) { // if current open order is SELL
            Print("Update SELL!");
            PrintABHL();
            
            // update it with new stop loss
            myOrderModify(currOrderTicket, OP_SELL, -1,true);
         } // end update SELL Order
      }
      else if (currOrderTicket == -1 && tpSellCandle==false) { // if no open orders
         
         RefreshRates();
         PrintABHL();
         
         if (numOfStopLosses == 0){
            Print("sending 1st entry order SELL");
         }
         else if (numOfStopLosses == 1){
            Print("sending 2st entry order SELL");
         }
         else if (numOfStopLosses == 2){
            Print("sending 3rd entry order SELL");
         }
         else if (numOfStopLosses == 3){
            Print("sending 4th entry order SELL");
         }
         else if (numOfStopLosses == 4){
            Print("sending 5th entry order SELL");
         }
         else{
            Print("THIS SHOULD NOT HAPPEN. ABOUT TO SEND A 6TH ENTRY ORDER!!");
         }
         
         Print("entry size = ", nextEntrySize);
         myOrderSend(OP_SELL, nextEntrySize);
         didHandleStopLoss = false;
      }
   }
   
   else{
      // neither BUY nor SELL condition! still update the stop loss!
      if(newCandle){
         if (currOrderTicket != -1 && currOrderType == OP_SELL) { // if current open order is SELL
            RefreshRates();
            PrintABHL();
            Print("Does not break high or low, still update your SELL stop loss!");
            
            // update it with new stop loss
            myOrderModify(currOrderTicket, OP_SELL, -1,true);
         }
      
         if (currOrderTicket != -1 && currOrderType == OP_BUY) { // if current open order is SELL
            RefreshRates();
            Print("Does not break high or low, still update your BUY stop loss!");
            
            // update it with new stop loss
            myOrderModify(currOrderTicket, OP_BUY, 1,true);
         }      
      }
   }
}


void myOrderSend(int side, double entrySize){
   double newStopLoss = -1;
   double newTakeProfit=-1;
   int tpSumConst=-1;
   int ticket = -1; 
   
   if(side == OP_BUY){
      ticket = OrderSend(Symbol(),side, entrySize, Ask, MAX_ALLOWED_SLIPPAGE, 0, 0, StringConcatenate(INITIAL_COMMENT,BUY_COMMENT),MAGIC_NUMBER,0,Green);
      tpSumConst = 1;
    }
   else if (side == OP_SELL){
      ticket = OrderSend(Symbol(),side, entrySize, Bid, MAX_ALLOWED_SLIPPAGE, 0, 0, StringConcatenate(INITIAL_COMMENT,BUY_COMMENT),MAGIC_NUMBER,0,Green);
      tpSumConst = -1;
   }                  
         
   if(ticket < 0){
      int sendError=GetLastError();
      Print("******************************************************************************");
      Print("Error with OrderSend");
      Print("Error code = ", sendError, "Description = ",ErrorDescription(sendError));
      //expertOn=false;
      
      Print("error entry size=",entrySize);
      Print("******************************************************************************\n");
   }
   else {
      myOrderModify(ticket, side, tpSumConst,false);
   }
}

void myOrderModify(int modifyTicket, int side, int tpSumConst, bool isUpdate){
   double newStopLoss = -1;
   double newTakeProfit = -1;
   
   OrderSelect(modifyTicket,SELECT_BY_TICKET);
   lastOrderTimeSent = OrderOpenTime();
   lastOrderTicket = modifyTicket;
      
   newStopLoss=firstEntryStopLoss(side,OrderOpenPrice());
   int variableTP = TAKE_PROFIT;
   
   // if I am in 2nd, 3rd, or 4th entry, or 5th entry
   if (numOfStopLosses == 1 || numOfStopLosses == 2 || numOfStopLosses == 3 || numOfStopLosses == 4){
      variableTP = SEC_THIR_FORTH_TP;
   }
   if (!isUpdate){
      Print("setting new take profit");
      newTakeProfit=OrderOpenPrice()+tpSumConst*myPoint*variableTP;
   }
   else {
      Print("take profit stays the same, only update stop loss");
      newTakeProfit=OrderTakeProfit();
   }   
   if (!OrderModify(modifyTicket, OrderOpenPrice(),newStopLoss,newTakeProfit,0,Red)){
      int modifyError=GetLastError();
      Print("******************************************************************************");
      Print("Error with OrderModify ticket# ",modifyTicket);
      Print("Error = ","code = ", modifyError, "Description = ",ErrorDescription(modifyError));
      Print("OrderOpenPrice = ", OrderOpenPrice());
      Print("error stop loss =",DoubleToStr(newStopLoss,Digits));
      Print("error take profit=",DoubleToStr(newTakeProfit,Digits));
      
      Print("OrderOpenPrice - stoploss = ", MathAbs(OrderOpenPrice() - newStopLoss));
      Print("OrderOpenPrice - takeprofit = ", MathAbs(OrderOpenPrice() - newTakeProfit));
      Print("error entry size=",OrderLots());
      PrintABHL( );
      Print("******************************************************************************\n");
      //expertOn=false;
   }
}

void PrintABHL(){
   Print("ASK = ",  DoubleToStr(Ask, Digits));
   Print("BID = ",  DoubleToStr(Bid, Digits));
   Print("HIGH= ",  DoubleToStr(High[1], Digits));
   Print("LOW = ",  DoubleToStr(Low[1],Digits));
}

double firstEntryStopLoss(int side,double openPrice){
   RefreshRates();
   
   double distance1= 0;
   double distance2=0;
   
   if(side==OP_BUY){
      distance1=MathAbs(openPrice-Low[1]);
      Print("distance1=",DoubleToStr(distance1,Digits));
      distance2=myPoint*FIRST_ENTRY_SL_CONSTANT*TAKE_PROFIT ;
      Print("distance2=",DoubleToStr(distance2,Digits));
      if (distance1 < distance2){
         Print("choosing distance 1");
      }
      else {
         Print("choosing distance 2");
      }
      
      if (MathMin(distance1,distance2) <MIN_STOP_DISTANCE){
         return (openPrice-MIN_STOP_DISTANCE);
      }
      return(openPrice-MathMin(distance1,distance2));
   }
   
   else if(side==OP_SELL){
      distance1=MathAbs(openPrice-High[1]);
      Print("distance1=",DoubleToStr(distance1,Digits));
      distance2=myPoint* FIRST_ENTRY_SL_CONSTANT*TAKE_PROFIT;
      Print("distance2=",DoubleToStr(distance2,Digits));
      
      if (distance1 < distance2){
         Print("choosing distance 1");
      }
      else {
         Print("choosing distance 2");
      }
      
      if (MathMin(distance1,distance2) <MIN_STOP_DISTANCE){
         return (openPrice+MIN_STOP_DISTANCE);
      }
      return(openPrice+MathMin(distance1,distance2));
   }
   
   return(-1);
   
}

bool sellCondition(){
   return (Bid < Low[1] && (Low[1]-Bid)<=0.0005);
}

bool buyCondition(){
   return (Ask > High[1] && (Ask-High[1]) <= 0.0005);
} 

 

 

 

 


void updateOrderAccounting(){
   bool existingOrders = false;
   
   if(OrdersTotal() > 1){
            Print("More than one market order!");
            Print("SHOULD NOT HAPPEN!!!!");
            //expertOn=false;
         }
   for(int i=0; i<OrdersTotal(); i++){      
      if (OrderSelect(i,SELECT_BY_POS)==true &&
          OrderMagicNumber()  == MAGIC_NUMBER &&
            (OrderType() == OP_BUY || OrderType() == OP_SELL)){
             
         existingOrders = true;
         totalMarketOrders++;
         
         currOrderTicket = OrderTicket();
         currOrderTimeSent = OrderOpenTime();
         currOrderType   = OrderType();
         currOrderPrice  = OrderOpenPrice();
         currOrderStopLoss = OrderStopLoss();
         currOrderTakeProfit = OrderTakeProfit();
         currOrderLots = OrderLots();
         
      }
   }
   
   if (!existingOrders){
      //Print("Resetting order properties to -1 because no orders exist");
      currOrderTicket = -1;
      datetime temp;
      currOrderTimeSent = temp;
      currOrderType   = -1;
      currOrderPrice  = -1;
      currOrderStopLoss = -1;
      currOrderTakeProfit = -1;
      currOrderLots = -1;
      totalMarketOrders = 0;
      currOCOTicket = -1;
   }
}

 

 

 

 

 

 

 

/**
* returns -1 if not a stop loss
*          0 if stop loss on BUY order
*          1 if stop loss on SELL order
*/
int stopLossHit(){
   if (currOrderTicket == -1){ // no open orders
      // possibility of stop loss, check further..
      //Print("Possibility you hit a stop loss on a ticket# ",lastOrderTicket);
      if (OrderSelect(lastOrderTicket,SELECT_BY_TICKET,MODE_HISTORY)){
         // at this point you know you hit a stop loss or take profit
         
         bool   HitTP = MathAbs( OrderTakeProfit() - OrderClosePrice() ) < MathAbs( OrderStopLoss() - OrderClosePrice() );
         
         // if you hit a stop loss
         if (!HitTP){
            Print("You hit a stop loss on ticket# ", OrderTicket());
            if (OrderType() == OP_BUY){
               Print("cannot allow to BUY again for remaining time of this candle");
               slBuyCandle = false;
            }
            else if (OrderType() == OP_SELL){
               Print("cannot allow to SELL again for the remaining time of this candle");
               slSellCandle = false;  
            }
            return (OrderType());
         }
         else {
            Print("You hit a TAKE PROFIT on ticket# ", OrderTicket());
            lastOrderTicket=-1; // wipe out last order ticket since it was take profit.
            numOfStopLosses = 0;
            numPipsLost = 0;
            totalPipsLost = 0;
            nextEntrySize = INITIAL_LOTS;
            if (OrderType() == OP_BUY){
               
               tpBuyCandle=true;
            }
            else{
               tpSellCandle=true;  
            }
            
            return (-1);
         }
      }
   }
   return (-1);
}

bool giveUpRetriesCondition() {
   return (numOfStopLosses >= MAX_ALLOWED_STOP_LOSSES ) ;
}

void handleStopLoss(int buyOrSell){
   numOfStopLosses++;
   
   Print("You have hit stop loss ", numOfStopLosses, " times.");
   OrderSelect(lastOrderTicket,SELECT_BY_TICKET,MODE_HISTORY);
   numPipsLost = getPipsLostForTicket(lastOrderTicket);
   Print("Current order pip loss = ", numPipsLost);
   totalPipsLost += numPipsLost;
   Print("Total pips lost so far = ", totalPipsLost);
   
   PrintABHL();
   
   // reached maximum retries
   if (giveUpRetriesCondition()){
      Print("No more re-entries. GIVING UP.");
      numOfStopLosses = 0;
      numPipsLost = 0;
      totalPipsLost = 0;
      
      
      datetime temp;       
      lastOrderTimeSent=temp;
      lastOrderTicket=-1;
      nextEntrySize=INITIAL_LOTS;
      
   }
   
   // prepare for re-entry, BUT DO NOT SEND ORDER HERE!!!!
   else {
      RefreshRates();

      OrderSelect(lastOrderTicket,SELECT_BY_TICKET,MODE_HISTORY);
      double previousOrderVolume=OrderLots();
      Print("Preparing for re-entry...");
      double tempMultiple=0;
      if (numOfStopLosses == 1) { // 2nd entry
         Print("2nd entry preparation..");  
         tempMultiple=SECOND_ENTRY_MULTIPLE;
      }
      else if (numOfStopLosses == 2) { // 3rd entry
         Print("3rd entry preparation..");
         tempMultiple=THIRD_ENTRY_MULTIPLE;
      }
      else if (numOfStopLosses == 3) { // 4th entry
         Print("4th entry preparation..");
         tempMultiple=FOURTH_ENTRY_MULTIPLE;
      }
      else if (numOfStopLosses == 4) { // 5th entry
         Print("5th entry preparation..");
         tempMultiple=FIFTH_ENTRY_MULTIPLE;
      }
      else{
         Print("THIS SHOULD NOT HAPPEN.  MORE ENTRIES THAN ALLOWED!!!");
      }
      Print("previous order volume =", previousOrderVolume);
      nextEntrySize = INITIAL_LOTS * tempMultiple;
      Print("next EntrySize = INITIAL_LOTS * multiple = ", INITIAL_LOTS, " * ", tempMultiple);
      nextEntrySize = MathRound(nextEntrySize);
      Print("next EntrySize rounded to: ", nextEntrySize);
   }
}

/*
   returns the number of pips
*/
double getPipsLostForTicket(int ticket){
   Print("getPipsLostForTicket()..computing pips lost");
   
   double offendingTicketOpenPrice=-1;
   double offendingTicketClosePrice=-1;
   double offendingTicketOrderLots=-1;
   int returnVal=-1;
   
   //get offending ticket
   OrderSelect(lastOrderTicket,SELECT_BY_TICKET,MODE_HISTORY);
   offendingTicketOpenPrice=OrderOpenPrice();
   offendingTicketClosePrice=OrderClosePrice();
   offendingTicketOrderLots=OrderLots();
   
   Print("ticket=",lastOrderTicket);
   Print("open price=",offendingTicketOpenPrice);
   Print("close price=",offendingTicketClosePrice);
   Print("order volume=",offendingTicketOrderLots);
   
   returnVal=10000*(MathAbs(offendingTicketOpenPrice-offendingTicketClosePrice));
   
   returnVal = returnVal*offendingTicketOrderLots/INITIAL_LOTS;
   
   Print("pips lost = ", returnVal);
   
   return(returnVal);
}

bool localtimeIsBetweenRange(int startHour, int endHour){
   int localHour = TimeHour(TimeLocal());
   if (startHour <= endHour){
   		if(localHour >=startHour && localHour <= endHour){
      		return (true);
   		}
   }
   // endHour < startHour (i.e. startHour=12 endHour=2)
   else {
   		// break up the checks
   		if(0 <= localHour && localHour <= endHour) {
   			return (true);
   		}
   		
   		if (startHour <= localHour && localHour <= 23){
   			return (true);
   		}
   }
   return (false);
}

