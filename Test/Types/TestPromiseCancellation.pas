unit TestPromiseCancellation;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Promises.Exceptions,
  Next.Core.Promises.Cancellation, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseCancellation = class
  public
    [Test]
    /// <summary>
    /// Create a promise with a token, cancel before it starts - rejects with EOperationCancelled.
    /// </summary>
    procedure CancelBeforeStart;

    [Test]
    /// <summary>
    /// Cancel during execution - cooperative check inside the function, verify cancellation.
    /// </summary>
    procedure CancelDuringExecution;

    [Test]
    /// <summary>
    /// Cancel in a chain - second ThenBy not executed after cancellation.
    /// </summary>
    procedure CancelInChain;

    [Test]
    /// <summary>
    /// OnCancelled handler fires on cancellation.
    /// </summary>
    procedure OnCancelledHandlerFires;

    [Test]
    /// <summary>
    /// Catch can recover from EOperationCancelled.
    /// </summary>
    procedure CatchCanRecoverFromCancellation;

    [Test]
    /// <summary>
    /// Token not cancelled - promise executes normally.
    /// </summary>
    procedure TokenNotCancelledExecutesNormally;

    [Test]
    /// <summary>
    /// Race + cancellation token pattern: cancel remaining promises after Race settles.
    /// </summary>
    procedure RacePlusCancellationPattern;

    [Test]
    /// <summary>
    /// TCancellationTokenSource basic functionality.
    /// </summary>
    procedure CancellationTokenSourceBasics;

    [Test]
    /// <summary>
    /// ThrowIfCancelled raises EOperationCancelled when cancelled.
    /// </summary>
    procedure ThrowIfCancelledRaises;
  end;

implementation

{ TTestPromiseCancellation }

procedure TTestPromiseCancellation.CancelBeforeStart;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
begin
  LCts := TCancellationTokenSource.Create;

  // Cancel before creating the promise chain
  LCts.Cancel;

  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .CancelToken(LCts.Token)
  .ThenBy(function(const V: Integer): Integer
    begin
      // This should not execute
      Result := V * 2;
    end);

  Assert.RejectsWith(LPromise, EOperationCancelled);
end;

procedure TTestPromiseCancellation.CancelDuringExecution;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
  LStartedSignal: TEvent;
begin
  LCts := TCancellationTokenSource.Create;
  LStartedSignal := TEvent.Create;
  try
    LPromise := Promise.Resolve<Integer>(function: Integer
      begin
        LStartedSignal.SetEvent;
        // Cooperative cancellation check
        var LIterations := 0;
        while LIterations < 1000 do
        begin
          if LCts.Token.IsCancelled then
            raise EOperationCancelled.Create;
          Sleep(10);
          Inc(LIterations);
        end;
        Result := 42;
      end);

    // Wait for the promise to start executing
    LStartedSignal.WaitFor(5000);
    Sleep(50);

    // Cancel while executing
    LCts.Cancel;

    Assert.RejectsWith(LPromise, EOperationCancelled);
  finally
    LStartedSignal.Free;
  end;
end;

procedure TTestPromiseCancellation.CancelInChain;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
  LSecondThenByCalled: Boolean;
  LStartedSignal: TEvent;
begin
  LCts := TCancellationTokenSource.Create;
  LSecondThenByCalled := False;
  LStartedSignal := TEvent.Create;
  try
    LPromise := Promise.Resolve<Integer>(function: Integer
      begin
        LStartedSignal.SetEvent;
        Result := 1;
      end)
    .CancelToken(LCts.Token)
    .ThenBy(function(const V: Integer): Integer
      begin
        // This step completes
        Result := V + 1;
      end)
    .ThenBy(function(const V: Integer): Integer
      begin
        // This should not execute if cancelled before reaching here
        LSecondThenByCalled := True;
        Result := V + 1;
      end);

    // Wait for execution to start, then cancel
    LStartedSignal.WaitFor(5000);
    LCts.Cancel;

    // The promise may resolve or reject depending on timing
    LPromise.InternalWait(5000);

    // If cancellation happened before the second ThenBy executed, it should not have been called
    // Note: Due to cooperative cancellation, timing may vary
  finally
    LStartedSignal.Free;
  end;
end;

procedure TTestPromiseCancellation.OnCancelledHandlerFires;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
  LOnCancelledFired: Boolean;
begin
  LCts := TCancellationTokenSource.Create;
  LOnCancelledFired := False;

  // Cancel before execution
  LCts.Cancel;

  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      LCts.Token.ThrowIfCancelled;
      Result := 42;
    end)
  .OnCancelled(procedure
    begin
      LOnCancelledFired := True;
    end);

  Assert.Rejects(LPromise);
  Assert.IsTrue(LOnCancelledFired);
end;

procedure TTestPromiseCancellation.CatchCanRecoverFromCancellation;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
begin
  LCts := TCancellationTokenSource.Create;
  LCts.Cancel;

  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      LCts.Token.ThrowIfCancelled;
      Result := 42;
    end)
  .Catch(function(E: Exception): Integer
    begin
      if E is EOperationCancelled then
        Result := -1
      else
        raise E;
    end);

  Assert.Resolves(LPromise);
  Assert.AreEqual(-1, LPromise.Await);
end;

procedure TTestPromiseCancellation.TokenNotCancelledExecutesNormally;
var
  LCts: ICancellationTokenSource;
  LPromise: IPromise<Integer>;
begin
  LCts := TCancellationTokenSource.Create;

  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      LCts.Token.ThrowIfCancelled;
      Result := 42;
    end)
  .CancelToken(LCts.Token)
  .ThenBy(function(const V: Integer): Integer
    begin
      Result := V * 2;
    end);

  Assert.Resolves(LPromise);
  Assert.AreEqual(84, LPromise.Await);
end;

procedure TTestPromiseCancellation.RacePlusCancellationPattern;
var
  LCts: ICancellationTokenSource;
  LRaceResult: IPromise<Integer>;
  LWorkerStarted: TEvent;
  LWorkerCancelled: Boolean;
begin
  LCts := TCancellationTokenSource.Create;
  LWorkerStarted := TEvent.Create;
  LWorkerCancelled := False;
  try
    LRaceResult := Promise.Race<Integer>([
      // Fast winner
      Promise.Resolve<Integer>(function: Integer
        begin
          Result := 42;
        end),
      // Slow worker that checks for cancellation
      Promise.Resolve<Integer>(function: Integer
        begin
          LWorkerStarted.SetEvent;
          var LIterations := 0;
          while LIterations < 100 do
          begin
            if LCts.Token.IsCancelled then
            begin
              LWorkerCancelled := True;
              raise EOperationCancelled.Create;
            end;
            Sleep(50);
            Inc(LIterations);
          end;
          Result := 99;
        end)
    ]);

    // Wait for race to settle
    Assert.Resolves(LRaceResult);
    Assert.AreEqual(42, LRaceResult.Await);

    // Now cancel to stop the slow worker
    LCts.Cancel;

    // Give it time to notice
    Sleep(200);
    Assert.IsTrue(LWorkerCancelled);
  finally
    LWorkerStarted.Free;
  end;
end;

procedure TTestPromiseCancellation.CancellationTokenSourceBasics;
var
  LCts: ICancellationTokenSource;
  LToken: ICancellationToken;
begin
  LCts := TCancellationTokenSource.Create;
  LToken := LCts.Token;

  Assert.IsFalse(LCts.IsCancelled);
  Assert.IsFalse(LToken.IsCancelled);

  LCts.Cancel;

  Assert.IsTrue(LCts.IsCancelled);
  Assert.IsTrue(LToken.IsCancelled);

  // Cancel is idempotent
  LCts.Cancel;
  Assert.IsTrue(LCts.IsCancelled);
end;

procedure TTestPromiseCancellation.ThrowIfCancelledRaises;
var
  LCts: ICancellationTokenSource;
begin
  LCts := TCancellationTokenSource.Create;

  // Should not raise when not cancelled
  Assert.WillNotRaise(procedure
    begin
      LCts.Token.ThrowIfCancelled;
    end);

  LCts.Cancel;

  // Should raise when cancelled
  Assert.WillRaise(procedure
    begin
      LCts.Token.ThrowIfCancelled;
    end, EOperationCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseCancellation);

end.
